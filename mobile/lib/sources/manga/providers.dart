import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../models/media.dart';
import '../../services/anilist.dart';
import '../../services/cache.dart';
import '../../services/log.dart';
import '../../services/net.dart';
import '../../services/store.dart';
import 'extensions.dart';

/// Port of the desktop `src/main/manga.ts` + `sources/*.ts`.
///
/// Every source answers the same questions (find the AniList title, list its
/// chapters, list a chapter's pages). All healthy sources are asked in
/// parallel and the one furthest along in readable chapters wins, unless the
/// user pinned one.

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

class MChapter {
  const MChapter({
    required this.id,
    required this.provider,
    this.number,
    this.title,
    this.volume,
    this.group,
    this.pages,
    this.publishedAt,
    this.externalUrl,
  });

  /// `provider:sourceId`
  final String id;
  final String provider;
  final String? number;
  final String? title;
  final String? volume;
  final String? group;
  final int? pages;
  final int? publishedAt;
  final String? externalUrl;

  double get sortKey => double.tryParse(number ?? '') ?? -1;

  String get label {
    final n = number == null ? 'Oneshot' : 'Chapter $number';
    final t = title?.trim();
    return t == null || t.isEmpty || t == n ? n : '$n · $t';
  }
}

class MPage {
  const MPage(this.url, {this.referer, this.ext, this.index = 0, this.pageUrl, this.imageUrl});

  /// Image URL, or `file://` for a downloaded page.
  final String url;
  final String? referer;

  /// Source id when the page comes from an installed extension; its image is
  /// then fetched through the extension (headers, cookies, de-scrambling).
  final String? ext;
  final int index;
  final String? pageUrl;
  final String? imageUrl;

  bool get isFile => url.startsWith('file://');
}

class ProviderSummary {
  const ProviderSummary({required this.provider, this.sourceId, this.title, this.chapterCount = 0, this.latest, this.error});

  final String provider;
  final String? sourceId;
  final String? title;
  final int chapterCount;
  final String? latest;
  final String? error;
}

class ChapterList {
  const ChapterList({required this.mediaId, required this.provider, required this.chapters, required this.providers});

  final int mediaId;
  final String? provider;
  final List<MChapter> chapters;
  final List<ProviderSummary> providers;
}

class ProviderInfo {
  const ProviderInfo(this.id, this.name, this.note, this.referer);

  final String id;
  final String name;
  final String note;
  final String referer;
}

const List<ProviderInfo> kProviders = [
  ProviderInfo('mangadex', 'MangaDex', 'Exact AniList match, scanlation groups', 'https://mangadex.org/'),
  ProviderInfo('asura', 'Asura Scans', 'Korean action manhwa', 'https://asurascans.com/'),
  ProviderInfo('flame', 'Flame Comics', 'Current Korean manhwa', 'https://flamecomics.xyz/'),
  ProviderInfo('weebcentral', 'WeebCentral', 'Huge manga, manhwa, manhua catalogue', 'https://weebcentral.com/'),
  ProviderInfo('mangapill', 'MangaPill', 'Licensed titles MangaDex lacks', 'https://mangapill.com/'),
];

/// Display name for a built-in or installed-extension provider id.
String providerName(String id) =>
    kProviders.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? Extensions.i.byProvider(id)?.name ?? id;

String refererFor(String provider) =>
    kProviders.firstWhere((p) => p.id == provider, orElse: () => kProviders.first).referer;

final _norm = RegExp(r'[^a-z0-9]');
String norm(String s) => s.toLowerCase().replaceAll(_norm, '');
String _normArticle(String s) => norm(s.toLowerCase().replaceFirst(RegExp(r'^(a|an|the)\s+'), ''));

String plainQuery(String title) => title
    .replaceAll(RegExp('[‘’ʼ`´]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‐‑‒–—―]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z]+);', caseSensitive: false), (m) {
      final code = m.group(1)!;
      if (code.startsWith('#')) {
        final n = code[1].toLowerCase() == 'x' ? int.tryParse(code.substring(2), radix: 16) : int.tryParse(code.substring(1));
        return n == null ? m.group(0)! : String.fromCharCode(n);
      }
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '}[code.toLowerCase()] ?? m.group(0)!;
    });

Future<T> _retry<T>(Future<T> Function() fn, [int attempts = 2]) async {
  for (var i = 0;; i++) {
    try {
      return await fn();
    } catch (_) {
      if (i + 1 >= attempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
    }
  }
}

Future<String> _text(String url, {Map<String, String> headers = const {}, int seconds = 15}) => _retry(() => Net.i.getText(
      url,
      NetOptions(headers: {'User-Agent': _ua, ...headers}, timeout: Duration(seconds: seconds)),
    ));

Future<dynamic> _json(String url, {Map<String, String> headers = const {}, int seconds = 15}) async =>
    jsonDecode(await _text(url, headers: headers, seconds: seconds));

List<String> titlesFor(MediaDetail m) {
  final out = <String>[];
  for (final t in [m.title.romaji, m.title.english, ...?m.synonyms?.take(2)]) {
    if (t != null && t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

typedef _Hit = ({String sourceId, String title});

abstract class _Source {
  Future<_Hit?> find(MediaDetail media);
  Future<List<MChapter>> chapters(String sourceId);
  Future<List<MPage>> pages(String sourceId, bool dataSaver);
  Future<void> ping();
}

// ── MangaDex ────────────────────────────────────────────────────────────────

class _MangaDex implements _Source {
  static const _api = 'https://api.mangadex.org';
  static const _h = {'User-Agent': 'PlayzAnime/2.0 (mobile reader)'};

  String get _ratings => (Store.i.settings.hideAdult
          ? ['safe', 'suggestive', 'erotica']
          : ['safe', 'suggestive', 'erotica', 'pornographic'])
      .map((r) => 'contentRating[]=$r')
      .join('&');

  @override
  Future<void> ping() async => _text('$_api/ping', headers: _h, seconds: 10);

  @override
  Future<_Hit?> find(MediaDetail media) async {
    _Hit? fallback;
    for (final title in titlesFor(media).take(3)) {
      final res = await _json('$_api/manga?title=${Uri.encodeQueryComponent(title)}&limit=10&$_ratings&order[relevance]=desc', headers: _h);
      for (final m in (res['data'] as List? ?? const [])) {
        final a = m['attributes'] as Map;
        final titles = Map<String, dynamic>.from(a['title'] as Map? ?? {});
        final name = (titles['en'] ?? (titles.values.isEmpty ? title : titles.values.first)).toString();
        final links = a['links'];
        if (links is Map && links['al']?.toString() == '${media.id}') return (sourceId: m['id'].toString(), title: name);
        final all = [...titles.values, for (final alt in (a['altTitles'] as List? ?? const [])) ...(alt as Map).values].map((e) => '$e');
        if (fallback == null && all.any((t) => norm(t) == norm(title))) fallback = (sourceId: m['id'].toString(), title: name);
      }
    }
    return fallback;
  }

  @override
  Future<List<MChapter>> chapters(String mangaId) async {
    final all = <Map>[];
    for (var offset = 0, page = 0; page < 12; page++, offset += 500) {
      final res = await _json(
        '$_api/manga/$mangaId/feed?translatedLanguage[]=en&limit=500&offset=$offset'
        '&order[volume]=asc&order[chapter]=asc&includes[]=scanlation_group&$_ratings',
        headers: _h,
        seconds: 20,
      );
      all.addAll((res['data'] as List? ?? const []).cast<Map>());
      if (offset + 500 >= ((res['total'] as num?) ?? 0)) break;
    }
    final byNumber = <String, Map>{};
    bool hosted(Map? c) => c != null && c['attributes']['externalUrl'] == null && ((c['attributes']['pages'] as num?) ?? 0) > 0;
    for (final c in all) {
      final key = c['attributes']['chapter']?.toString() ?? 'oneshot:${c['id']}';
      final prev = byNumber[key];
      if (prev == null || (hosted(c) && !hosted(prev))) byNumber[key] = c;
    }
    return [
      for (final c in byNumber.values)
        MChapter(
          id: 'mangadex:${c['id']}',
          provider: 'mangadex',
          number: c['attributes']['chapter']?.toString(),
          title: (c['attributes']['title']?.toString().isEmpty ?? true) ? null : c['attributes']['title'].toString(),
          volume: c['attributes']['volume']?.toString(),
          group: (c['relationships'] as List? ?? const [])
              .cast<Map>()
              .where((r) => r['type'] == 'scanlation_group')
              .map((r) => (r['attributes'] as Map?)?['name']?.toString())
              .firstOrNull,
          pages: (c['attributes']['pages'] as num?)?.toInt(),
          publishedAt: DateTime.tryParse('${c['attributes']['readableAt'] ?? c['attributes']['publishAt'] ?? ''}')?.millisecondsSinceEpoch,
          externalUrl: c['attributes']['externalUrl']?.toString(),
        ),
    ];
  }

  @override
  Future<List<MPage>> pages(String id, bool dataSaver) async {
    final res = await _json('$_api/at-home/server/$id', headers: _h);
    final ch = res['chapter'] as Map?;
    if (ch == null) return const [];
    final saver = dataSaver && (ch['dataSaver'] as List?)?.isNotEmpty == true;
    final files = (saver ? ch['dataSaver'] : ch['data']) as List? ?? const [];
    return [for (final f in files) MPage('${res['baseUrl']}/${saver ? 'data-saver' : 'data'}/${ch['hash']}/$f')];
  }
}

// ── MangaPill ───────────────────────────────────────────────────────────────

class _MangaPill implements _Source {
  static const _base = 'https://mangapill.com';
  static const _ref = '$_base/';

  Future<List<({String path, String title, String? alt, int? year})>> search(String q) async {
    final doc = html.parse(await _text('$_base/search?q=${Uri.encodeQueryComponent(plainQuery(q))}'));
    final out = <({String path, String title, String? alt, int? year})>[];
    final seen = <String>{};
    for (final card in doc.querySelectorAll('a[href^="/manga/"]')) {
      final path = card.attributes['href'] ?? '';
      final t = card.querySelector('.font-black');
      if (t == null || seen.contains(path)) continue;
      seen.add(path);
      final alt = card.querySelector('.text-xs')?.text.trim();
      final tags = card.parent?.querySelectorAll('.rounded') ?? const [];
      final year = tags.map((e) => e.text.trim()).where((s) => RegExp(r'^\d{4}$').hasMatch(s)).map(int.parse).firstOrNull;
      out.add((path: path, title: decodeEntities(t.text.trim()), alt: alt == null || alt.isEmpty ? null : decodeEntities(alt), year: year));
    }
    return out;
  }

  @override
  Future<void> ping() async => search('naruto');

  @override
  Future<_Hit?> find(MediaDetail media) async {
    final year = media.startDate?.year;
    bool fits(int? y) => year == null || y == null || (y - year).abs() <= 1;
    _Hit? loose;
    for (final title in titlesFor(media).take(3)) {
      final hits = (await search(title)).where((h) => !RegExp(r'\bnovel\b', caseSensitive: false).hasMatch('${h.title} ${h.alt ?? ''}')).toList();
      final t = norm(title);
      List<String> names(h) => [norm(h.title), if (h.alt != null) norm(h.alt!)];
      final exact = hits.where((h) => names(h).contains(t)).toList();
      final pick = exact.where((h) => fits(h.year)).firstOrNull ?? exact.firstOrNull;
      if (pick != null) return (sourceId: pick.path, title: pick.title);
      if (loose == null) {
        final l = hits.where((h) =>
            year != null &&
            h.year != null &&
            fits(h.year) &&
            names(h).any((n) => (n.length < t.length ? n.length : t.length) >= 8 && (n.startsWith(t) || t.startsWith(n)))).firstOrNull;
        if (l != null) loose = (sourceId: l.path, title: l.title);
      }
    }
    return loose;
  }

  @override
  Future<List<MChapter>> chapters(String path) async {
    final doc = html.parse(await _text('$_base$path'));
    final seen = <String>{};
    final list = <MChapter>[];
    for (final a in doc.querySelectorAll('a[href^="/chapters/"]')) {
      final href = a.attributes['href'] ?? '';
      if (!seen.add(href)) continue;
      final n = RegExp(r'chapter\s+([\d.]+)', caseSensitive: false).firstMatch(a.text)?.group(1);
      list.add(MChapter(id: 'mangapill:$href', provider: 'mangapill', number: n));
    }
    return list.reversed.toList();
  }

  @override
  Future<List<MPage>> pages(String path, bool _) async {
    final doc = html.parse(await _text('$_base$path'));
    return [
      for (final img in doc.querySelectorAll('img.js-page'))
        if (RegExp('^https?://').hasMatch(img.attributes['data-src'] ?? img.attributes['src'] ?? ''))
          MPage(img.attributes['data-src'] ?? img.attributes['src']!, referer: _ref),
    ];
  }
}

// ── WeebCentral ─────────────────────────────────────────────────────────────

class _WeebCentral implements _Source {
  static const _base = 'https://weebcentral.com';
  static const _ref = '$_base/';
  static const _hx = {'HX-Request': 'true', 'Referer': _ref};
  static const _kinds = ['manga', 'manhwa', 'manhua', 'oel'];
  static const _stop = {'the', 'and', 'for', 'with', 'from', 'into', 'wa', 'no', 'ga', 'wo', 'ni', 'de', 'to'};

  Future<List<({String id, String title, String? kind, int? year})>> search(String q) async {
    final body = await _text(
      '$_base/search/data?text=${Uri.encodeQueryComponent(plainQuery(q))}&sort=Best%20Match&order=Descending&official=Any&display_mode=Minimal%20Display&limit=16&offset=0',
      headers: _hx,
    );
    final out = <({String id, String title, String? kind, int? year})>[];
    for (final article in body.split('<article').skip(1)) {
      final link = RegExp(r'href="https://weebcentral\.com/series/([A-Z0-9]+)/[^"]*"[^>]*data-tip="([^"]*)"').firstMatch(article);
      if (link == null) continue;
      final meta = RegExp(r'<div>([^<]+)</div>').allMatches(article).map((m) => m.group(1)!.trim()).toList();
      out.add((
        id: link.group(1)!,
        title: decodeEntities(link.group(2)!),
        kind: meta.firstOrNull,
        year: meta.map(int.tryParse).whereType<int>().where((n) => n > 1900 && n < 2100).firstOrNull,
      ));
    }
    return out;
  }

  String _keywords(String title) => title
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 2 && !_stop.contains(w.toLowerCase()))
      .take(6)
      .join(' ');

  @override
  Future<void> ping() async => search('one piece');

  @override
  Future<_Hit?> find(MediaDetail media) async {
    final year = media.startDate?.year;
    for (final title in titlesFor(media).take(3)) {
      final t = _normArticle(title);
      for (final q in {plainQuery(title), _keywords(title)}.where((q) => q.isNotEmpty)) {
        final hits = (await search(q)).where((h) => h.kind == null || _kinds.contains(h.kind!.toLowerCase()));
        final exact = hits.where((h) => _normArticle(h.title) == t).toList();
        final pick = exact.where((h) => year == null || h.year == null || (h.year! - year).abs() <= 1).firstOrNull ??
            (exact.length == 1 ? exact.first : null);
        if (pick != null) return (sourceId: pick.id, title: pick.title);
      }
    }
    return null;
  }

  @override
  Future<List<MChapter>> chapters(String id) async {
    final body = await _text('$_base/series/$id/full-chapter-list', headers: _hx, seconds: 20);
    final re = RegExp(r'<a href="(?:https://weebcentral\.com)?/chapters/([A-Z0-9]+)"[\s\S]*?<span class="">([^<]+)</span>[\s\S]*?<time[^>]*datetime="([^"]+)"');
    final seen = <String>{};
    final list = <MChapter>[];
    for (final m in re.allMatches(body)) {
      if (!seen.add(m.group(1)!)) continue;
      final label = decodeEntities(m.group(2)!.trim());
      final plain = RegExp(r'^(chapter|episode|ch\.?)\s*[\d.]+$', caseSensitive: false).hasMatch(label);
      list.add(MChapter(
        id: 'weebcentral:${m.group(1)}',
        provider: 'weebcentral',
        number: RegExp(r'(\d+(?:\.\d+)?)').firstMatch(label)?.group(1),
        title: plain ? null : label,
        publishedAt: DateTime.tryParse(m.group(3)!)?.millisecondsSinceEpoch,
      ));
    }
    return list.reversed.toList();
  }

  @override
  Future<List<MPage>> pages(String id, bool _) async {
    final body = await _text('$_base/chapters/$id/images?is_prev=False&current_page=1&reading_style=long_strip', headers: _hx);
    return RegExp(r'<img[^>]+src="(https://[^"]+)"[^>]*alt="Page \d+"')
        .allMatches(body)
        .map((m) => MPage(decodeEntities(m.group(1)!), referer: _ref))
        .toList();
  }
}

// ── Asura ───────────────────────────────────────────────────────────────────

class _Asura implements _Source {
  static const _base = 'https://asurascans.com';
  static const _ref = '$_base/';

  Future<List<({String id, String title})>> search(String q) async {
    final body = await _text('$_base/browse/comics?q=${Uri.encodeQueryComponent(q)}',
        headers: {'Referer': _ref, 'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'});
    final out = <({String id, String title})>[];
    final seen = <String>{};
    for (final m in RegExp(r'<a[^>]*href="/comics/([^"]+)"[^>]*>([\s\S]*?)</a>', caseSensitive: false).allMatches(body)) {
      final slug = m.group(1)!;
      if (seen.contains(slug) || slug == 'comics' || slug.contains('/chapter/')) continue;
      final clean = decodeEntities(m.group(2)!.replaceAll(RegExp('<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());
      if (clean.isEmpty || RegExp(r'^\d+(\.\d+)?$').hasMatch(clean)) continue;
      seen.add(slug);
      out.add((id: slug, title: clean));
    }
    return out;
  }

  @override
  Future<void> ping() async => search('solo');

  @override
  Future<_Hit?> find(MediaDetail media) async {
    for (final title in titlesFor(media)) {
      final hits = await search(title).catchError((_) => <({String id, String title})>[]);
      if (hits.isEmpty) continue;
      final t = _normArticle(title);
      final hit = hits.where((h) {
        final hn = _normArticle(h.title);
        return hn == t;
      }).firstOrNull;
      if (hit != null) return (sourceId: hit.id, title: hit.title);
    }
    return null;
  }

  @override
  Future<List<MChapter>> chapters(String slug) async {
    final body = await _text('$_base/comics/$slug', headers: {'Referer': _ref}, seconds: 20);
    final seen = <String>{};
    final list = <MChapter>[];
    for (final m in RegExp('href="(/comics/${RegExp.escape(slug)}/chapter/([^"]+))"').allMatches(body)) {
      final raw = m.group(2)!;
      if (!seen.add(raw)) continue;
      final n = double.tryParse(raw);
      list.add(MChapter(
        id: 'asura:$slug/$raw',
        provider: 'asura',
        number: n == null ? raw : (n == n.roundToDouble() ? '${n.toInt()}' : '$n'),
        group: 'Asura Scans',
      ));
    }
    list.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return list;
  }

  @override
  Future<List<MPage>> pages(String id, bool _) async {
    final slash = id.lastIndexOf('/');
    final body = await _text('$_base/comics/${id.substring(0, slash)}/chapter/${id.substring(slash + 1)}', headers: {'Referer': _ref});
    var urls = RegExp(r'''https://[^"'\s\\<>&]+/asura-images/chapters/[^"'\s\\<>&]+/[0-9]+/[^"'\s\\<>&]+\.webp(?:\?[^"'\s\\<>&]*)?''')
        .allMatches(body)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
    if (urls.isEmpty) {
      final all = RegExp(r'https://[^"\s\\]+/[^"\s\\]+\.(?:webp|jpg|jpeg|png)(?:\?[^"\s\\]*)?').allMatches(body).map((m) => m.group(0)!).toSet().toList();
      final f = all.where((u) => u.contains('chapter') || u.contains('storage') || u.contains('cdn')).toList();
      urls = f.isEmpty ? all : f;
    }
    return [for (final u in urls) MPage(u, referer: _ref)];
  }
}

// ── Flame ───────────────────────────────────────────────────────────────────

class _Flame implements _Source {
  static const _base = 'https://flamecomics.xyz';
  static const _ref = '$_base/';
  List<Map>? _catalogue;
  int _at = 0;

  Future<List<Map>> _list() async {
    if (_catalogue != null && DateTime.now().millisecondsSinceEpoch - _at < 6 * 3600000) return _catalogue!;
    final data = await _json('$_base/api/series', headers: {'Referer': _ref});
    _catalogue = data is List ? data.cast<Map>() : const [];
    _at = DateTime.now().millisecondsSinceEpoch;
    return _catalogue!;
  }

  @override
  Future<void> ping() async {
    _catalogue = null;
    await _list();
  }

  @override
  Future<_Hit?> find(MediaDetail media) async {
    final wanted = titlesFor(media).map(_normArticle).where((s) => s.isNotEmpty).toSet();
    final hit = (await _list()).where((s) => wanted.contains(_normArticle(decodeEntities('${s['label']}')))).firstOrNull;
    return hit == null ? null : (sourceId: '${hit['id']}', title: decodeEntities('${hit['label']}'));
  }

  @override
  Future<List<MChapter>> chapters(String seriesId) async {
    final body = await _text('$_base/series/$seriesId', headers: {'Referer': _ref}, seconds: 20);
    final seen = <String>{};
    final list = <MChapter>[];
    for (final chunk in body.split('"chapter_id":').skip(1)) {
      final head = chunk.length > 600 ? chunk.substring(0, 600) : chunk;
      final token = RegExp(r'"token":"([a-f0-9]+)"').firstMatch(head)?.group(1);
      final raw = RegExp(r'"chapter":"([^"]+)"').firstMatch(head)?.group(1);
      if (token == null || !head.contains('"series_id":$seriesId,') || !seen.add(token)) continue;
      final title = RegExp(r'"title":"((?:[^"\\]|\\.)*)"').firstMatch(head)?.group(1);
      final released = int.tryParse(RegExp(r'"release_date":(\d+)').firstMatch(head)?.group(1) ?? '');
      final n = double.tryParse(raw ?? '');
      String? t;
      if (title != null) {
        try {
          t = decodeEntities(jsonDecode('"$title"') as String);
        } catch (_) {
          t = title;
        }
      }
      list.add(MChapter(
        id: 'flame:$seriesId/$token',
        provider: 'flame',
        number: raw == null ? null : (n == null ? raw : (n == n.roundToDouble() ? '${n.toInt()}' : '$n')),
        title: t,
        group: 'Flame Comics',
        publishedAt: released == null ? null : released * 1000,
      ));
    }
    list.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return list;
  }

  @override
  Future<List<MPage>> pages(String id, bool _) async {
    final parts = id.split('/');
    final body = await _text('$_base/series/${parts[0]}/${parts[1]}', headers: {'Referer': _ref});
    final re = RegExp('https://cdn\\.flamecomics\\.xyz/uploads/images/series/${parts[0]}/${parts[1]}/[^"\\\\\\s?]+(?:\\?\\d+)?');
    return [for (final u in re.allMatches(body).map((m) => m.group(0)!).toSet()) MPage(u, referer: _ref)];
  }
}

// ── Installed extensions ────────────────────────────────────────────────────

class _Ext implements _Source {
  _Ext(this.s);

  final InstalledSource s;

  @override
  Future<void> ping() async => Extensions.i.popular(s, 1);

  @override
  Future<_Hit?> find(MediaDetail media) async {
    final wanted = {for (final t in titlesFor(media)) _normArticle(t)};
    for (final title in titlesFor(media).take(2)) {
      final hits = await Extensions.i.search(s, plainQuery(title), 1);
      final hit = hits.where((m) => wanted.contains(_normArticle(m.title))).firstOrNull;
      if (hit != null) return (sourceId: hit.url, title: hit.title);
    }
    return null;
  }

  @override
  Future<List<MChapter>> chapters(String url) => Extensions.i.chapters(s, url);

  @override
  Future<List<MPage>> pages(String url, bool _) => Extensions.i.pages(s, url);
}

// ── Orchestration ───────────────────────────────────────────────────────────

class MangaProviders {
  MangaProviders._();

  static final MangaProviders i = MangaProviders._();
  final _log = Log('manga');
  final _cache = TtlCache<Object>(200);

  final Map<String, _Source> _sources = {
    'mangadex': _MangaDex(),
    'asura': _Asura(),
    'flame': _Flame(),
    'weebcentral': _WeebCentral(),
    'mangapill': _MangaPill(),
  };

  static const _richness = {'mangadex': 4, 'asura': 3, 'flame': 2, 'weebcentral': 1, 'mangapill': 0};

  final Map<String, ({bool ok, int ms, int at, String? error})> health = {};

  Set<String> get _disabled => Store.i.disabledSources;

  _Source? _source(String id) {
    final builtin = _sources[id];
    if (builtin != null) return builtin;
    final ext = id.startsWith('x') ? Extensions.i.byProvider(id) : null;
    return ext == null ? null : _Ext(ext);
  }

  /// Built-ins plus installed extensions. With many extensions installed only
  /// the first [_autoExt] are asked automatically (recommended ones first), so
  /// opening a title doesn't fire a hundred searches; "Search every extension"
  /// in the source sheet passes `all`.
  List<String> _ids({bool all = false}) {
    final ext = [...Extensions.i.searchable]..sort((a, b) {
        int rank(InstalledSource s) => kRecommended.contains(s.pkg) ? 0 : 1;
        return rank(a) - rank(b);
      });
    return [..._sources.keys, for (final s in all ? ext : ext.take(_autoExt)) s.provider];
  }

  static const _autoExt = 10;

  Future<void> checkHealth({bool force = false}) async {
    await Future.wait(_sources.entries.map((e) async {
      final known = health[e.key];
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && known != null && now - known.at < 600000) return;
      final sw = Stopwatch()..start();
      try {
        await e.value.ping().timeout(const Duration(seconds: 10));
        health[e.key] = (ok: true, ms: sw.elapsedMilliseconds, at: now, error: null);
      } catch (err) {
        health[e.key] = (ok: false, ms: sw.elapsedMilliseconds, at: now, error: '$err');
      }
    }));
  }

  String? _latest(List<MChapter> list) {
    double? best;
    for (final c in list) {
      if (c.externalUrl != null) continue;
      final n = double.tryParse(c.number ?? '');
      if (n != null && (best == null || n > best)) best = n;
    }
    return best == null ? null : (best == best.roundToDouble() ? '${best.toInt()}' : '$best');
  }

  Future<({ProviderSummary summary, List<MChapter> chapters})> _load(String provider, MediaDetail media, bool force) {
    final down = health[provider];
    if (!force && down != null && !down.ok && DateTime.now().millisecondsSinceEpoch - down.at < 600000) {
      return Future.value((summary: ProviderSummary(provider: provider, error: 'Unreachable right now'), chapters: <MChapter>[]));
    }
    return _cache
        .wrap('chapters:$provider:${media.id}', 20 * 60000, () async {
          try {
            final src = _source(provider)!;
            final hit = await src.find(media).timeout(const Duration(seconds: 25));
            final chapters = hit == null ? <MChapter>[] : await src.chapters(hit.sourceId).timeout(const Duration(seconds: 30));
            return (
              summary: ProviderSummary(
                  provider: provider, sourceId: hit?.sourceId, title: hit?.title, chapterCount: chapters.length, latest: _latest(chapters)),
              chapters: chapters,
            );
          } catch (err) {
            _log.warn('$provider failed for ${media.id}', err);
            return (summary: ProviderSummary(provider: provider, error: '$err'), chapters: <MChapter>[]);
          }
        }, force);
  }

  /// Every enabled source in parallel; the furthest-along readable list wins
  /// unless [provider] (per title) or the Settings default picks one.
  Future<ChapterList> chapterList(int mediaId, {String? provider, bool force = false, bool all = false}) async {
    final media = await AniList.i.media(mediaId);
    unawaited(checkHealth().catchError((_) {}));
    final ids = _ids(all: all).where((id) => !_disabled.contains(id) || id == provider).toList();
    if (provider != null && !ids.contains(provider) && _source(provider) != null) ids.add(provider);
    final results = await Future.wait(ids.map((id) => _load(id, media, force)));
    int readable(r) => (r.chapters as List<MChapter>).where((c) => c.externalUrl == null).length;
    final pref = Store.i.settings.mangaProvider;
    ({ProviderSummary summary, List<MChapter> chapters})? chosen;
    if (provider != null) {
      chosen = results.where((r) => r.summary.provider == provider).firstOrNull;
    } else if (pref != 'auto') {
      chosen = results.where((r) => r.summary.provider == pref && readable(r) > 0).firstOrNull;
    }
    if (chosen == null && results.isNotEmpty) {
      final sorted = [...results]..sort((a, b) {
          final diff = (double.tryParse(b.summary.latest ?? '') ?? -1) - (double.tryParse(a.summary.latest ?? '') ?? -1);
          if (diff.abs() >= 1) return diff.sign.toInt();
          final r = readable(b) - readable(a);
          return r != 0 ? r : (_richness[b.summary.provider] ?? 0) - (_richness[a.summary.provider] ?? 0);
        });
      chosen = sorted.first;
    }
    return ChapterList(
      mediaId: mediaId,
      provider: chosen?.summary.provider,
      chapters: chosen?.chapters ?? const [],
      providers: results.map((r) => r.summary).toList(),
    );
  }

  Future<List<MPage>> pages(MChapter chapter) {
    final i = chapter.id.indexOf(':');
    final provider = chapter.id.substring(0, i);
    final sourceId = chapter.id.substring(i + 1);
    final src = _source(provider);
    if (src == null) return Future.error(StateError('That chapter comes from a source PlayzAnime no longer uses.'));
    final saver = Store.i.settings.dataSaver;
    return _cache
        .wrap('pages:${chapter.id}:$saver', 5 * 60000, () => src.pages(sourceId, saver), false)
        .then((v) => (v as List).cast<MPage>());
  }

  void clear() {
    _cache.clear();
    health.clear();
  }
}
