import 'dart:convert';

import '../models/media.dart';
import 'cache.dart';
import 'log.dart';
import 'net.dart';

/// AniList's public GraphQL API.
///
/// Ported from `src/main/anilist.ts`: same endpoint, same queries, same TTLs,
/// same "never send an explicit null" rule (AniList answers some list filters
/// sent as null with a 500, while omitting the variable means "no filter").
class AniList {
  AniList._();

  static final AniList i = AniList._();

  static const String endpoint = 'https://graphql.anilist.co';
  static const int _minute = 60 * 1000;

  final _cache = TtlCache<Object>(400);
  final _log = Log('anilist');

  bool _hideAdult = true;

  bool get hideAdult => _hideAdult;

  set hideAdult(bool value) {
    if (_hideAdult != value) _cache.clear();
    _hideAdult = value;
    _onAdultChanged?.call();
  }

  /// The feed cache is keyed by `hideAdult`, so flipping it must also drop the
  /// on-disk copy. The store wires this up.
  void Function()? _onAdultChanged;

  set onAdultChanged(void Function() cb) => _onAdultChanged = cb;

  void clearCache() => _cache.clear();

  bool? get _adultVar => _hideAdult ? false : null;

  static const String cardFragment = '''
  fragment card on Media {
    id
    idMal
    type
    isAdult
    title { romaji english native userPreferred }
    coverImage { extraLarge large medium color }
    bannerImage
    format
    status
    episodes
    duration
    chapters
    volumes
    countryOfOrigin
    season
    seasonYear
    genres
    averageScore
    popularity
    nextAiringEpisode { episode airingAt timeUntilAiring }
    studios(isMain: true) { nodes { name } }
    startDate { year month day }
  }
''';

  /// The AniList season that is airing on the given date.
  static ({MediaSeason season, int year}) currentSeason([DateTime? date]) {
    final d = date ?? DateTime.now();
    final m = d.month; // 1-12
    final season = m <= 3
        ? MediaSeason.winter
        : m <= 6
        ? MediaSeason.spring
        : m <= 9
        ? MediaSeason.summer
        : MediaSeason.fall;
    return (season: season, year: d.year);
  }

  Future<Map<String, dynamic>> _gql(String query, Map<String, dynamic> variables) async {
    // Nulls are never sent: see the class comment.
    final vars = <String, dynamic>{};
    variables.forEach((k, v) {
      if (v != null) vars[k] = v;
    });

    return Net.i.retry(() async {
      final body = <String, dynamic>{'query': '$cardFragment\n$query', 'variables': vars};
      final res = await Net.i.postJson(endpoint, body, const NetOptions(timeout: Duration(seconds: 15)));
      final errors = res['errors'];
      if (errors is List && errors.isNotEmpty) {
        final messages = [
          for (final e in errors)
            if (e is Map && e['message'] != null) e['message'].toString(),
        ];
        if (messages.any((m) => m.toLowerCase().contains('rate limit'))) {
          _log.warn('rate limited by AniList');
        }
        _log.warn('AniList error: ${messages.join('; ')}');
        throw StateError(messages.join('; '));
      }
      final data = res['data'];
      if (data is! Map) throw StateError('AniList returned no data');
      final out = Map<String, dynamic>.from(data);
      _lastData = out;
      return out;
    }, attempts: 3);
  }

  // ── Instant start ─────────────────────────────────────────────────────────
  // The home feeds are saved to disk. On launch the last copy shows immediately
  // while a fresh one loads in the background, so the app never opens to
  // skeletons. The store owns the disk half — it just hands us two callbacks.

  /// Persists the raw GraphQL `data` object for a feed key. Wired to the store.
  void Function(String key, Map<String, dynamic> data)? onFeed;

  /// Reads it back, with the time it was written. Wired to the store.
  ({Map<String, dynamic> data, int at})? Function(String key)? readFeed;

  // (feeds are served stale-while-revalidate; see _instant)

  /// Returns the saved copy when it is younger than 24h, and refreshes in the
  /// background. The returned future never waits on the network in that case.
  Future<T> _instant<T>({
    required String key,
    required bool force,
    required Future<T> Function() fetch,
    required T Function(Map<String, dynamic> data) decode,
  }) {
    final firstLoad = _cache.get(key) == null;
    final saved = force ? null : readFeed?.call(key);

    final fresh = fetch().then((value) {
      final raw = _lastData;
      if (raw != null) onFeed?.call(key, raw);
      return value;
    });

    // Stale-while-revalidate: any saved copy shows at once (and offline); the
    // request refreshes the cache behind it.
    if (firstLoad && saved != null) {
      // Deliberately unawaited: the caller gets the cached feed now and the
      // request lands when it lands. A failure here is not the user's problem.
      fresh.catchError((Object err) {
        _log.warn('background refresh of $key failed', err);
        return decode(saved.data);
      });
      return Future.value(decode(saved.data));
    }
    return fresh;
  }

  /// The `data` object from the most recent `_gql` call, so `_instant` can
  /// persist exactly what the server sent without re-serialising the models.
  Map<String, dynamic>? _lastData;

  // ── Home feeds ────────────────────────────────────────────────────────────

  static const String _homeQuery = '''
  query (\$season: MediaSeason, \$year: Int, \$isAdult: Boolean) {
    trending: Page(page: 1, perPage: 24) {
      media(type: ANIME, sort: [TRENDING_DESC, POPULARITY_DESC], status_not: NOT_YET_RELEASED, isAdult: \$isAdult) {
        ...card
        description(asHtml: false)
      }
    }
    season: Page(page: 1, perPage: 24) {
      media(type: ANIME, sort: [POPULARITY_DESC], season: \$season, seasonYear: \$year, isAdult: \$isAdult, status_not: NOT_YET_RELEASED) {
        ...card
      }
    }
    top: Page(page: 1, perPage: 24) {
      media(type: ANIME, sort: [SCORE_DESC], status_not: NOT_YET_RELEASED, isAdult: \$isAdult, popularity_greater: 30000) {
        ...card
      }
    }
  }
''';

  Future<HomeFeed> home({bool force = false}) {
    final label = currentSeason();
    return _instant<HomeFeed>(
      key: 'home:$_hideAdult',
      force: force,
      fetch: () => _cache.wrap(
        'home:$_hideAdult',
        10 * _minute,
        () async {
          final data = await _gql(_homeQuery, {
            'season': mediaSeasonToWire(label.season),
            'year': label.year,
            'isAdult': _adultVar,
          });
          return HomeFeed.fromGql(data, label);
        },
        force,
      ),
      decode: (data) => HomeFeed.fromGql(data, currentSeason()),
    );
  }

  static const String _mangaHomeQuery = '''
  query (\$isAdult: Boolean) {
    trending: Page(page: 1, perPage: 24) {
      media(type: MANGA, sort: [TRENDING_DESC, POPULARITY_DESC], format_not_in: [NOVEL], isAdult: \$isAdult) {
        ...card
        description(asHtml: false)
      }
    }
    manhwa: Page(page: 1, perPage: 24) {
      media(type: MANGA, countryOfOrigin: "KR", sort: [TRENDING_DESC], format_not_in: [NOVEL], isAdult: \$isAdult) {
        ...card
      }
    }
    top: Page(page: 1, perPage: 24) {
      media(type: MANGA, sort: [SCORE_DESC], format_not_in: [NOVEL], isAdult: \$isAdult, popularity_greater: 20000) {
        ...card
      }
    }
  }
''';

  Future<MangaFeed> mangaHome({bool force = false}) {
    return _instant<MangaFeed>(
      key: 'mangaHome:$_hideAdult',
      force: force,
      fetch: () => _cache.wrap(
        'mangaHome:$_hideAdult',
        10 * _minute,
        () async {
          final data = await _gql(_mangaHomeQuery, {'isAdult': _adultVar});
          return MangaFeed.fromGql(data);
        },
        force,
      ),
      decode: MangaFeed.fromGql,
    );
  }

  // ── Browse & search ───────────────────────────────────────────────────────

  static const String _browseQuery = '''
  query (
    \$type: MediaType, \$page: Int, \$perPage: Int, \$search: String, \$sort: [MediaSort], \$genres: [String],
    \$formats: [MediaFormat], \$formatsNot: [MediaFormat], \$season: MediaSeason, \$year: Int, \$status: MediaStatus,
    \$statusNot: MediaStatus, \$isAdult: Boolean, \$country: CountryCode
  ) {
    Page(page: \$page, perPage: \$perPage) {
      pageInfo { hasNextPage }
      media(
        type: \$type, search: \$search, sort: \$sort, genre_in: \$genres, format_in: \$formats, format_not_in: \$formatsNot,
        season: \$season, seasonYear: \$year, status: \$status, status_not: \$statusNot, isAdult: \$isAdult,
        countryOfOrigin: \$country
      ) {
        ...card
        description(asHtml: false)
      }
    }
  }
''';

  Future<Paged<Media>> browse(BrowseFilters filters, {bool force = false}) {
    final type = filters.type ?? MediaType.anime;
    final search = (filters.search ?? '').trim().isEmpty ? null : filters.search!.trim();
    final sort = filters.sort ?? (search != null ? SortKey.searchMatch : SortKey.trendingDesc);
    final isManga = type == MediaType.manga;

    final vars = <String, dynamic>{
      'type': mediaTypeToWire(type),
      'page': filters.page,
      'perPage': filters.perPage > 50 ? 50 : filters.perPage,
      'search': search,
      'sort': sort == SortKey.searchMatch
          ? ['SEARCH_MATCH', 'POPULARITY_DESC']
          : [sortKeyToWire(sort), 'POPULARITY_DESC'],
      'genres': (filters.genres?.isEmpty ?? true) ? null : filters.genres,
      // Novels have nothing to read in the app; music videos nothing to watch.
      'formatsNot': isManga ? ['NOVEL'] : ['MUSIC'],
      'formats': (filters.formats?.isEmpty ?? true) ? null : filters.formats,
      'season': isManga ? null : (filters.season == null ? null : mediaSeasonToWire(filters.season!)),
      'year': isManga ? null : filters.year,
      'status': filters.status?.wire,
      // Unreleased anime have nothing to play, so they only appear when asked
      // for explicitly or when searching.
      'statusNot': (filters.status != null || search != null || isManga) ? null : 'NOT_YET_RELEASED',
      'isAdult': _adultVar,
      'country': isManga ? filters.country : null,
    };

    final key = 'browse:${jsonEncode(vars)}';
    final ttl = (search != null ? 5 : 10) * _minute;
    return _cache.wrap(key, ttl, () async {
      final data = await _gql(_browseQuery, vars);
      final page = data['Page'];
      final items = mediaListFromGql(page);
      final info = page is Map ? page['pageInfo'] : null;
      final hasNext = info is Map && info['hasNextPage'] == true;
      return Paged(items: items, page: filters.page, hasNextPage: hasNext);
    }, force);
  }

  // ── Media detail ──────────────────────────────────────────────────────────

  static const String _mediaQuery = '''
  query (\$id: Int) {
    Media(id: \$id) {
      ...card
      description(asHtml: false)
      synonyms
      source(version: 3)
      endDate { year month day }
      tags { name rank isMediaSpoiler }
      trailer { id site }
      rankings { rank type allTime season year context }
      streamingEpisodes { title thumbnail }
      staff(perPage: 4, sort: [RELEVANCE]) { edges { role node { name { full } } } }
      relations {
        edges {
          relationType(version: 2)
          node { ...card }
        }
      }
      recommendations(perPage: 14, sort: [RATING_DESC]) {
        nodes { mediaRecommendation { ...card } }
      }
    }
  }
''';

  Future<MediaDetail> media(int id, {bool force = false}) {
    return _cache.wrap(
      'media:$id',
      30 * _minute,
      () async {
        final data = await _gql(_mediaQuery, {'id': id});
        final raw = data['Media'];
        if (raw is! Map) throw StateError('No media $id');
        final detail = MediaDetail.fromJson(Map<String, dynamic>.from(raw));
        return detail.copyWithFiltered(hideAdult: _hideAdult);
      },
      force,
    );
  }

  // ── Airing schedule ───────────────────────────────────────────────────────

  static const String _scheduleQuery = '''
  query (\$page: Int, \$from: Int, \$to: Int) {
    Page(page: \$page, perPage: 50) {
      pageInfo { hasNextPage }
      airingSchedules(airingAt_greater: \$from, airingAt_lesser: \$to, sort: [TIME]) {
        id
        episode
        airingAt
        media { ...card }
      }
    }
  }
''';

  Future<List<AiringItem>> schedule(int from, int to, {bool force = false}) {
    return _cache.wrap(
      'schedule:$from:$to:$_hideAdult',
      15 * _minute,
      () async {
        final items = <AiringItem>[];
        for (var page = 1; page <= 8; page++) {
          final data = await _gql(_scheduleQuery, {'page': page, 'from': from, 'to': to});
          final p = data['Page'];
          if (p is! Map) break;
          for (final row in (p['airingSchedules'] as List? ?? const [])) {
            if (row is Map) items.add(AiringItem.fromScheduleJson(Map<String, dynamic>.from(row)));
          }
          final info = p['pageInfo'];
          if (!(info is Map && info['hasNextPage'] == true)) break;
        }
        return [
          for (final i in items)
            if (!(_hideAdult && (i.media.isAdult ?? false))) i,
        ];
      },
      force,
    );
  }

}

/// Drops the entries the detail screen should not show. Kept out of the model so
/// the same filter can be reused for cached and freshly-fetched data.
extension MediaDetailFilter on MediaDetail {
  MediaDetail copyWithFiltered({required bool hideAdult}) {
    // Light novels have nothing to read or watch in the app.
    final rels = relations?.where((r) => r.node.format != 'NOVEL' && !(hideAdult && (r.node.isAdult ?? false))).toList();
    final recs = recommendations?.where((m) => !(hideAdult && (m.isAdult ?? false))).toList();
    return MediaDetail(
      id: id,
      idMal: idMal,
      type: type,
      title: title,
      coverImage: coverImage,
      bannerImage: bannerImage,
      format: format,
      status: status,
      episodes: episodes,
      duration: duration,
      chapters: chapters,
      volumes: volumes,
      countryOfOrigin: countryOfOrigin,
      season: season,
      seasonYear: seasonYear,
      genres: genres,
      averageScore: averageScore,
      popularity: popularity,
      description: description,
      isAdult: isAdult,
      nextAiringEpisode: nextAiringEpisode,
      studios: studios,
      staff: staff,
      startDate: startDate,
      synonyms: synonyms,
      source: source,
      endDate: endDate,
      tags: tags,
      trailerId: trailerId,
      trailerSite: trailerSite,
      relations: (rels?.isEmpty ?? true) ? null : rels,
      recommendations: (recs?.isEmpty ?? true) ? null : recs,
      streamingEpisodes: streamingEpisodes,
      rankings: rankings,
    );
  }
}

/// Genre list used by the Discover filter chips and the Home genre block.
const List<String> anilistGenres = [
  'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror', 'Mahou Shoujo',
  'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life',
  'Sports', 'Supernatural', 'Thriller',
];
