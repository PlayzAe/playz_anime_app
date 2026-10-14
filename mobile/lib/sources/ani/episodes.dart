import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../models/media.dart';
import '../../models/stream.dart';
import '../../services/anilist.dart';
import '../../services/cache.dart';
import '../../services/log.dart';
import '../../services/net.dart';

/// Port of the desktop `src/main/episodes.ts` + `sources/anikoto.ts`.
///
/// AniList entry → anikoto series (MAL id makes it exact) → megaplay embed
/// per episode. If no provider match exists, AniList-id embeds are used, the
/// same fallback the desktop app ships.

const _api = 'https://anikotoapi.site';
const _searchDomains = ['https://anikoto.cz', 'https://anikototv.to'];
const kMegaplay = 'https://megaplay.buzz';
const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

final _log = Log('episodes');
final _lists = TtlCache<EpisodeList>(200);
final _stills = TtlCache<Map<int, String>>(100);

String _norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

String decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z]+);', caseSensitive: false), (m) {
      final code = m.group(1)!;
      if (code.startsWith('#')) {
        final n = code[1].toLowerCase() == 'x' ? int.tryParse(code.substring(2), radix: 16) : int.tryParse(code.substring(1));
        return n == null ? m.group(0)! : String.fromCharCode(n);
      }
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '}[code.toLowerCase()] ?? m.group(0)!;
    });

Future<String> _get(String url, {int seconds = 12, Map<String, String> headers = const {}}) =>
    Net.i.getText(url, NetOptions(headers: {'User-Agent': _ua, ...headers}, timeout: Duration(seconds: seconds)));

// ── anikoto ─────────────────────────────────────────────────────────────────

typedef _Hit = ({int id, String title, String type, int subEpisodes});

class _SourceEpisode {
  const _SourceEpisode(this.number, this.title, this.sub, this.dub);
  final int number;
  final String? title;
  final String? sub;
  final String? dub;
}

class _SourceSeries {
  const _SourceSeries(this.id, this.malId, this.aniId, this.episodes);
  final int id;
  final int? malId;
  final String? aniId;
  final List<_SourceEpisode> episodes;
}

Future<List<_Hit>> _search(String keyword) async {
  for (final domain in _searchDomains) {
    try {
      final doc = html.parse(await _get('$domain/search?keyword=${Uri.encodeQueryComponent(keyword)}'));
      final hits = <_Hit>[];
      final seen = <int>{};
      for (final item in doc.querySelectorAll('#list-items .item, .items .item')) {
        final id = int.tryParse(item.querySelector('[data-tip]')?.attributes['data-tip'] ?? '');
        if (id == null || id <= 0 || !seen.add(id)) continue;
        final name = item.querySelector('.info .name') ?? item.querySelector('.name') ?? item.querySelector('a');
        hits.add((
          id: id,
          title: decodeEntities(name?.text.trim() ?? ''),
          type: item.querySelector('.meta .right')?.text.trim() ?? '',
          subEpisodes: int.tryParse((item.querySelector('.ep-status.sub')?.text ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0,
        ));
      }
      if (hits.isNotEmpty) return hits;
    } catch (e) {
      _log.warn('search failed on $domain', e);
    }
  }
  return const [];
}

int _score(String targetTitle, String targetFormat, int? targetEps, _Hit hit) {
  var s = 0;
  final t = _norm(targetTitle), h = _norm(hit.title);
  if (h == t) {
    s += 120;
  } else if (h.startsWith(t)) {
    s += 35;
  } else if (h.contains(t)) {
    s += 15;
  } else {
    s -= 20;
  }
  final fmt = (targetFormat.isEmpty ? 'TV' : targetFormat).toUpperCase();
  final type = hit.type.toUpperCase();
  if (type.isNotEmpty && (fmt.contains(type) || type.contains(fmt))) {
    s += 60;
  } else if (fmt == 'TV' && const ['MOVIE', 'SPECIAL', 'OVA'].contains(type)) {
    s -= 60;
  }
  final eps = hit.subEpisodes;
  if (targetEps != null && targetEps > 1) {
    if (eps == targetEps) {
      s += 100;
    } else if (eps > 1) {
      s += 40;
    } else if (eps == 1 && fmt == 'TV') {
      s -= 50;
    }
  } else if (targetEps == 1 || fmt == 'MOVIE') {
    if (eps == 1) {
      s += 50;
    } else if (eps > 1) {
      s -= 30;
    }
  } else if (fmt == 'TV' && eps > 1) {
    s += 45;
  }
  return s;
}

Future<_SourceSeries?> _series(int id) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final json = jsonDecode(await _get('$_api/series/$id')) as Map<String, dynamic>;
      final data = json['data'] as Map?;
      final anime = data?['anime'] as Map?;
      if (anime == null) return null;
      final mal = int.tryParse('${anime['mal_id']}');
      return _SourceSeries(
        id,
        mal != null && mal > 0 ? mal : null,
        anime['ani_id'] == null ? null : '${anime['ani_id']}',
        [
          for (final e in (data!['episodes'] as List? ?? const []))
            _SourceEpisode(
              (e['number'] as num).toInt(),
              e['title'] == null ? null : decodeEntities('${e['title']}'),
              (e['embed_url'] as Map?)?['sub']?.toString(),
              (e['embed_url'] as Map?)?['dub']?.toString(),
            ),
        ],
      );
    } catch (e) {
      if (attempt == 2) _log.warn('series $id failed', e);
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
  }
  return null;
}

Future<_SourceSeries?> _match(List<String> titles, String format, int? episodes, int? malId) async {
  final scored = <int, ({_Hit hit, int score})>{};
  final loaded = <int, _SourceSeries?>{};
  List<({_Hit hit, int score})> top() => (scored.values.toList()..sort((a, b) => b.score - a.score)).take(6).toList();

  for (final title in titles) {
    for (final hit in await _search(title)) {
      final s = _score(title, format, episodes, hit);
      final prev = scored[hit.id];
      if (prev == null || prev.score < s) scored[hit.id] = (hit: hit, score: s);
    }
    if (malId != null) {
      final pending = top().where((r) => !loaded.containsKey(r.hit.id)).toList();
      for (var i = 0; i < pending.length; i += 2) {
        final pair = pending.skip(i).take(2).toList();
        final results = await Future.wait(pair.map((r) => _series(r.hit.id)));
        for (var j = 0; j < pair.length; j++) {
          loaded[pair[j].hit.id] = results[j];
        }
        final exact = results.where((s) => s != null && s.malId == malId).firstOrNull;
        if (exact != null) return exact;
      }
    } else if ((top().firstOrNull?.score ?? 0) >= 200) {
      break;
    }
  }
  for (final r in top()) {
    if (r.score < 40) break;
    final s = loaded.containsKey(r.hit.id) ? loaded[r.hit.id] : await _series(r.hit.id);
    if (s == null || s.episodes.isEmpty) continue;
    if (malId != null && s.malId != null && s.malId != malId) continue;
    final onlyFull = s.episodes.length == 1 && (s.episodes.first.title ?? '').trim().toLowerCase() == 'full';
    if (format == 'TV' && (episodes ?? 0) > 1 && onlyFull) continue;
    return s;
  }
  return null;
}

// ── episodes ────────────────────────────────────────────────────────────────

final _generic = RegExp(r'^(episode\s*\d+|ep\.?\s*\d+|full|\d+)$', caseSensitive: false);

Map<int, ({String? title, String? thumbnail})> _streamingIndex(MediaDetail media) {
  final out = <int, ({String? title, String? thumbnail})>{};
  for (final se in media.streamingEpisodes ?? const <StreamingEpisode>[]) {
    final m = RegExp(r'^episode\s+(\d+)(?:\s*[-–:]\s*(.+))?$', caseSensitive: false).firstMatch((se.title ?? '').trim());
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    out.putIfAbsent(n, () => (title: m.group(2)?.trim(), thumbnail: se.thumbnail));
  }
  return out;
}

int _expected(MediaDetail m) {
  if (m.format == 'MOVIE') return 1;
  if (m.episodes != null) return m.episodes!;
  if (m.nextAiringEpisode != null) return (m.nextAiringEpisode!.episode - 1).clamp(1, 100000);
  return 12;
}

Future<Map<int, String>> _kitsuStills(int malId, List<int> need) => _stills.wrap('stills:$malId:${need.first}', 24 * 3600000, () async {
      const base = 'https://kitsu.app/api/edge';
      const h = {'Accept': 'application/vnd.api+json'};
      final out = <int, String>{};
      final mapping = jsonDecode(await _get('$base/mappings?filter[externalSite]=myanimelist/anime&filter[externalId]=$malId&include=item', headers: h, seconds: 8));
      final kitsuId = (mapping['included'] as List? ?? const []).cast<Map>().where((i) => i['type'] == 'anime').map((i) => '${i['id']}').firstOrNull;
      if (kitsuId == null) return out;
      final pages = need.map((n) => (n - 1) ~/ 20).toSet().take(10);
      await Future.wait(pages.map((p) async {
        try {
          final res = jsonDecode(await _get('$base/anime/$kitsuId/episodes?page[limit]=20&page[offset]=${p * 20}&sort=number', headers: h, seconds: 8));
          for (final e in (res['data'] as List? ?? const [])) {
            final a = e['attributes'] as Map?;
            final n = (a?['number'] as num?)?.toInt();
            final url = (a?['thumbnail'] as Map?)?['original']?.toString();
            if (n != null && url != null) out[n] = url;
          }
        } catch (_) {}
      }));
      return out;
    });

Future<EpisodeList> listEpisodes(int mediaId, {bool force = false}) =>
    _lists.wrap('eps:$mediaId', 20 * 60000, () => _load(mediaId), force);

void clearEpisodeCache() {
  _lists.clear();
  _stills.clear();
}

Future<EpisodeList> _load(int mediaId) async {
  final media = await AniList.i.media(mediaId);
  final isMovie = media.format == 'MOVIE';
  final titles = [media.title.romaji, media.title.english].whereType<String>().where((t) => t.isNotEmpty).toList();
  final streaming = _streamingIndex(media);

  _SourceSeries? source;
  try {
    source = await _match(titles, media.format ?? 'TV', _expected(media), media.idMal).timeout(const Duration(seconds: 40));
  } catch (e) {
    _log.warn('match failed for $mediaId', e);
  }

  var episodes = <Episode>[];
  if (source != null) {
    final sorted = [...source.episodes]..sort((a, b) => a.number - b.number);
    for (final e in isMovie ? sorted.take(1) : sorted) {
      final n = isMovie ? 1 : e.number;
      final meta = streaming[n];
      final own = (e.title ?? '').trim();
      episodes.add(Episode(
        number: n,
        title: isMovie ? 'Full movie' : (own.isNotEmpty && !_generic.hasMatch(own) ? own : meta?.title ?? 'Episode $n'),
        subUrl: e.sub ?? (source.aniId != null ? '$kMegaplay/stream/ani/${source.aniId}/$n/sub' : null),
        dubUrl: e.dub,
        thumbnail: meta?.thumbnail,
      ));
    }
    _log.info('matched $mediaId → ${source.id} (${episodes.length} episodes)');
  }

  // ani.zip (TVDB stills and titles) covers new seasons and donghua that
  // AniList's streaming list and Kitsu don't have yet.
  if (!isMovie && episodes.any((e) => e.thumbnail == null)) {
    try {
      final zip = await _aniZip(mediaId).timeout(const Duration(seconds: 6));
      episodes = [
        for (final e in episodes)
          e.thumbnail != null || zip[e.number] == null
              ? e
              : Episode(
                  number: e.number,
                  title: _generic.hasMatch(e.title.trim()) ? (zip[e.number]!.title ?? e.title) : e.title,
                  subUrl: e.subUrl,
                  dubUrl: e.dubUrl,
                  thumbnail: zip[e.number]!.image ?? e.thumbnail,
                ),
      ];
    } catch (_) {}
  }

  final need = episodes.where((e) => e.thumbnail == null).map((e) => e.number).toList();
  if (need.isNotEmpty && media.idMal != null && !isMovie) {
    try {
      final stills = await _kitsuStills(media.idMal!, need).timeout(const Duration(seconds: 6));
      episodes = [
        for (final e in episodes)
          e.thumbnail != null || stills[e.number] == null
              ? e
              : Episode(number: e.number, title: e.title, subUrl: e.subUrl, dubUrl: e.dubUrl, thumbnail: stills[e.number]),
      ];
    } catch (_) {}
  }

  final fallback = episodes.isEmpty;
  if (fallback) {
    final total = _expected(media);
    episodes = [
      for (var n = 1; n <= total; n++)
        Episode(
          number: n,
          title: isMovie ? 'Full movie' : streaming[n]?.title ?? 'Episode $n',
          subUrl: '$kMegaplay/stream/ani/$mediaId/$n/sub',
          thumbnail: streaming[n]?.thumbnail,
        ),
    ];
    _log.warn('no provider match for $mediaId; using AniList-id embeds');
  }

  // The AniList-id embed answers "Error - MegaPlay" for titles it doesn't carry.
  var available = true;
  if (fallback) {
    try {
      final page = await _get('$kMegaplay/stream/ani/$mediaId/1/sub', headers: const {'Referer': '$kMegaplay/'}, seconds: 8);
      available = !isMegaplayError(page);
    } catch (_) {}
  }

  return EpisodeList(
    mediaId: mediaId,
    sourceId: source?.id,
    fallback: fallback,
    available: available,
    hasDub: episodes.any((e) => e.dubUrl != null),
    episodes: episodes,
  );
}

/// MegaPlay serves a 200 page titled "Error - MegaPlay" for missing titles.
bool isMegaplayError(String html) => RegExp(r'<title>\s*Error\b', caseSensitive: false).hasMatch(html);

final _zip = TtlCache<Map<int, ({String? title, String? image})>>(60);

/// Episode stills and titles from ani.zip (TVDB), keyed by episode number.
Future<Map<int, ({String? title, String? image})>> _aniZip(int anilistId) => _zip.wrap('zip:$anilistId', 24 * 3600000, () async {
      final out = <int, ({String? title, String? image})>{};
      final raw = jsonDecode(await _get('https://api.ani.zip/mappings?anilist_id=$anilistId', seconds: 6));
      final eps = raw is Map ? raw['episodes'] : null;
      if (eps is! Map) return out;
      for (final entry in eps.entries) {
        final n = int.tryParse('${entry.key}');
        final e = entry.value;
        if (n == null || e is! Map) continue;
        final title = (e['title'] as Map?)?['en']?.toString();
        out[n] = (title: title == null || title.trim().isEmpty ? null : title.trim(), image: e['image']?.toString());
      }
      return out;
    });
