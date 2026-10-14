import 'json.dart';

/// Media types, mirroring `src/shared/types.ts`.
enum MediaType { anime, manga }

const Map<String, MediaType> _mediaTypeFromWire = {'ANIME': MediaType.anime, 'MANGA': MediaType.manga};

String mediaTypeToWire(MediaType t) => t == MediaType.anime ? 'ANIME' : 'MANGA';

/// `TV`, `TV_SHORT`, `MOVIE`, `SPECIAL`, `OVA`, `ONA`, `MUSIC`, `MANGA`, `NOVEL`, `ONE_SHOT`.
/// Kept as the wire string: AniList is the only producer and the UI prints a
/// localised label, so an enum would only add a translation layer.
typedef MediaFormat = String;

enum MediaStatus { finished, releasing, notYetReleased, cancelled, hiatus }

const Map<String, MediaStatus> _statusFromWire = {
  'FINISHED': MediaStatus.finished,
  'RELEASING': MediaStatus.releasing,
  'NOT_YET_RELEASED': MediaStatus.notYetReleased,
  'CANCELLED': MediaStatus.cancelled,
  'HIATUS': MediaStatus.hiatus,
};

enum MediaSeason { winter, spring, summer, fall }

const Map<String, MediaSeason> _seasonFromWire = {
  'WINTER': MediaSeason.winter,
  'SPRING': MediaSeason.spring,
  'SUMMER': MediaSeason.summer,
  'FALL': MediaSeason.fall,
};

String mediaSeasonToWire(MediaSeason s) => switch (s) {
  MediaSeason.winter => 'WINTER',
  MediaSeason.spring => 'SPRING',
  MediaSeason.summer => 'SUMMER',
  MediaSeason.fall => 'FALL',
};

class MediaTitle {
  const MediaTitle({this.romaji, this.english, this.native, this.userPreferred});

  final String? romaji;
  final String? english;
  final String? native;
  final String? userPreferred;

  factory MediaTitle.fromJson(Map<String, dynamic> j) => MediaTitle(
    romaji: j.str('romaji'),
    english: j.str('english'),
    native: j.str('native'),
    userPreferred: j.str('userPreferred'),
  );

  Map<String, dynamic> toJson() => {
    if (romaji != null) 'romaji': romaji,
    if (english != null) 'english': english,
    if (native != null) 'native': native,
  };
}

class MediaCover {
  const MediaCover({this.extraLarge, this.large, this.medium, this.color});

  final String? extraLarge;
  final String? large;
  final String? medium;
  final String? color;

  factory MediaCover.fromJson(Map<String, dynamic> j) => MediaCover(
    extraLarge: j.str('extraLarge'),
    large: j.str('large'),
    medium: j.str('medium'),
    color: j.str('color'),
  );

  Map<String, dynamic> toJson() => {
    if (extraLarge != null) 'extraLarge': extraLarge,
    if (large != null) 'large': large,
    if (medium != null) 'medium': medium,
    if (color != null) 'color': color,
  };
}

class FuzzyDate {
  const FuzzyDate({this.year, this.month, this.day});

  final int? year;
  final int? month;
  final int? day;

  factory FuzzyDate.fromJson(Map<String, dynamic> j) =>
      FuzzyDate(year: j.integer('year'), month: j.integer('month'), day: j.integer('day'));

  Map<String, dynamic> toJson() => {
    if (year != null) 'year': year,
    if (month != null) 'month': month,
    if (day != null) 'day': day,
  };
}

class NextAiring {
  const NextAiring({required this.episode, required this.airingAt, required this.timeUntilAiring});

  final int episode;
  final int airingAt;
  final int timeUntilAiring;

  factory NextAiring.fromJson(Map<String, dynamic> j) => NextAiring(
    episode: j.integer('episode') ?? 0,
    airingAt: j.integer('airingAt') ?? 0,
    timeUntilAiring: j.integer('timeUntilAiring') ?? 0,
  );
}

class Media {
  const Media({
    required this.id,
    required this.title,
    this.idMal,
    this.type,
    this.coverImage,
    this.bannerImage,
    this.format,
    this.status,
    this.episodes,
    this.duration,
    this.chapters,
    this.volumes,
    this.countryOfOrigin,
    this.season,
    this.seasonYear,
    this.genres,
    this.averageScore,
    this.popularity,
    this.description,
    this.isAdult,
    this.nextAiringEpisode,
    this.studios,
    this.staff,
    this.startDate,
  });

  final int id;
  final int? idMal;
  final MediaType? type;
  final MediaTitle title;
  final MediaCover? coverImage;
  final String? bannerImage;
  final MediaFormat? format;
  final MediaStatus? status;
  final int? episodes;
  final int? duration;
  final int? chapters;
  final int? volumes;
  final String? countryOfOrigin;
  final MediaSeason? season;
  final int? seasonYear;
  final List<String>? genres;
  final int? averageScore;
  final int? popularity;
  final String? description;
  final bool? isAdult;
  final NextAiring? nextAiringEpisode;
  final List<String>? studios;
  final List<StaffEdge>? staff;
  final FuzzyDate? startDate;

  factory Media.fromJson(Map<String, dynamic> j) => Media(
    id: j.integer('id') ?? 0,
    idMal: j.integer('idMal'),
    type: _mediaTypeFromWire[j.str('type')],
    title: MediaTitle.fromJson(j.obj('title') ?? const {}),
    coverImage: j.obj('coverImage') == null ? null : MediaCover.fromJson(j.obj('coverImage')!),
    bannerImage: j.str('bannerImage'),
    format: j.str('format'),
    status: _statusFromWire[j.str('status')],
    episodes: j.integer('episodes'),
    duration: j.integer('duration'),
    chapters: j.integer('chapters'),
    volumes: j.integer('volumes'),
    countryOfOrigin: j.str('countryOfOrigin'),
    season: _seasonFromWire[j.str('season')],
    seasonYear: j.integer('seasonYear'),
    genres: j.stringList('genres'),
    averageScore: j.integer('averageScore'),
    popularity: j.integer('popularity'),
    description: j.str('description'),
    isAdult: j.boolean('isAdult'),
    nextAiringEpisode: j.obj('nextAiringEpisode') == null
        ? null
        : NextAiring.fromJson(j.obj('nextAiringEpisode')!),
    studios: _studiosFromJson(j.obj('studios')),
    staff: _staffFromJson(j.obj('staff')),
    startDate: j.obj('startDate') == null ? null : FuzzyDate.fromJson(j.obj('startDate')!),
  );

  static List<String>? _studiosFromJson(Map<String, dynamic>? j) {
    final nodes = j?.list('nodes');
    if (nodes == null) return null;
    return [
      for (final n in nodes)
        if (n is Map) ?(n['name'] as String?),
    ];
  }

  static List<StaffEdge>? _staffFromJson(Map<String, dynamic>? j) {
    final edges = j?.list('edges');
    if (edges == null) return null;
    return [
      for (final e in edges)
        if (e is Map) StaffEdge.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  MediaSnapshot toSnapshot() => MediaSnapshot(
    id: id,
    type: type ?? MediaType.anime,
    title: title.english ?? title.romaji ?? 'Untitled',
    romaji: title.romaji,
    native: title.native,
    cover: coverImage?.large ?? coverImage?.medium ?? '',
    banner: bannerImage,
    color: coverImage?.color,
    format: format,
    episodes: episodes,
    chapters: chapters,
    year: seasonYear ?? startDate?.year,
    status: status,
  );
}

class StaffEdge {
  const StaffEdge({required this.role, required this.name});

  final String role;
  final String name;

  factory StaffEdge.fromJson(Map<String, dynamic> j) => StaffEdge(
    role: j.str('role') ?? '',
    name: j.obj('node')?.obj('name')?.str('full') ?? '',
  );
}

class MediaRelation {
  const MediaRelation({required this.relationType, required this.node});

  final String relationType;
  final Media node;

  factory MediaRelation.fromJson(Map<String, dynamic> j) => MediaRelation(
    relationType: j.str('relationType') ?? '',
    node: Media.fromJson(j.obj('node') ?? const {}),
  );
}

class StreamingEpisode {
  const StreamingEpisode({this.title, this.thumbnail});

  final String? title;
  final String? thumbnail;

  factory StreamingEpisode.fromJson(Map<String, dynamic> j) =>
      StreamingEpisode(title: j.str('title'), thumbnail: j.str('thumbnail'));
}

class MediaDetail extends Media {
  const MediaDetail({
    required super.id,
    required super.title,
    super.idMal,
    super.type,
    super.coverImage,
    super.bannerImage,
    super.format,
    super.status,
    super.episodes,
    super.duration,
    super.chapters,
    super.volumes,
    super.countryOfOrigin,
    super.season,
    super.seasonYear,
    super.genres,
    super.averageScore,
    super.popularity,
    super.description,
    super.isAdult,
    super.nextAiringEpisode,
    super.studios,
    super.staff,
    super.startDate,
    this.synonyms,
    this.source,
    this.endDate,
    this.tags,
    this.trailerId,
    this.trailerSite,
    this.relations,
    this.recommendations,
    this.streamingEpisodes,
    this.rankings,
  });

  final List<String>? synonyms;
  final String? source;
  final FuzzyDate? endDate;
  final List<MediaTag>? tags;
  final String? trailerId;
  final String? trailerSite;
  final List<MediaRelation>? relations;
  final List<Media>? recommendations;
  final List<StreamingEpisode>? streamingEpisodes;
  final List<Ranking>? rankings;

  factory MediaDetail.fromJson(Map<String, dynamic> j) {
    final base = Media.fromJson(j);
    final relations = <MediaRelation>[];
    for (final e in j.obj('relations')?.list('edges') ?? const []) {
      if (e is Map) relations.add(MediaRelation.fromJson(Map<String, dynamic>.from(e)));
    }
    final recs = <Media>[];
    for (final n in j.obj('recommendations')?.list('nodes') ?? const []) {
      if (n is Map) {
        final rec = n['mediaRecommendation'];
        if (rec is Map) recs.add(Media.fromJson(Map<String, dynamic>.from(rec)));
      }
    }
    final tags = <MediaTag>[];
    for (final t in j.list('tags') ?? const []) {
      if (t is Map) tags.add(MediaTag.fromJson(Map<String, dynamic>.from(t)));
    }
    final ranks = <Ranking>[];
    for (final r in j.list('rankings') ?? const []) {
      if (r is Map) ranks.add(Ranking.fromJson(Map<String, dynamic>.from(r)));
    }

    return MediaDetail(
      id: base.id,
      idMal: base.idMal,
      type: base.type,
      title: base.title,
      coverImage: base.coverImage,
      bannerImage: base.bannerImage,
      format: base.format,
      status: base.status,
      episodes: base.episodes,
      duration: base.duration,
      chapters: base.chapters,
      volumes: base.volumes,
      countryOfOrigin: base.countryOfOrigin,
      season: base.season,
      seasonYear: base.seasonYear,
      genres: base.genres,
      averageScore: base.averageScore,
      popularity: base.popularity,
      description: base.description,
      isAdult: base.isAdult,
      nextAiringEpisode: base.nextAiringEpisode,
      studios: base.studios,
      staff: base.staff,
      startDate: base.startDate,
      synonyms: j.stringList('synonyms'),
      source: j.str('source'),
      endDate: j.obj('endDate') == null ? null : FuzzyDate.fromJson(j.obj('endDate')!),
      trailerId: j.obj('trailer')?.str('id'),
      trailerSite: j.obj('trailer')?.str('site'),
      relations: relations.isEmpty ? null : relations,
      recommendations: recs.isEmpty ? null : recs,
      tags: tags.isEmpty ? null : tags,
      streamingEpisodes: [
        for (final s in j.list('streamingEpisodes') ?? const [])
          if (s is Map) StreamingEpisode.fromJson(Map<String, dynamic>.from(s)),
      ],
      rankings: ranks.isEmpty ? null : ranks,
    );
  }
}

class MediaTag {
  const MediaTag({required this.name, required this.rank, required this.isMediaSpoiler});

  final String name;
  final int rank;
  final bool isMediaSpoiler;

  factory MediaTag.fromJson(Map<String, dynamic> j) => MediaTag(
    name: j.str('name') ?? '',
    rank: j.integer('rank') ?? 0,
    isMediaSpoiler: j.boolean('isMediaSpoiler') ?? false,
  );
}

class Ranking {
  const Ranking({
    required this.rank,
    required this.type,
    required this.allTime,
    required this.context,
    this.season,
    this.year,
  });

  final int rank;
  final String type; // RATED | POPULAR
  final bool allTime;
  final String context;
  final String? season;
  final int? year;

  factory Ranking.fromJson(Map<String, dynamic> j) => Ranking(
    rank: j.integer('rank') ?? 0,
    type: j.str('type') ?? 'RATED',
    allTime: j.boolean('allTime') ?? false,
    context: j.str('context') ?? '',
    season: j.str('season'),
    year: j.integer('year'),
  );
}

/// The fields kept offline so lists render without a network round-trip.
class MediaSnapshot {
  MediaSnapshot({
    required this.id,
    this.type = MediaType.anime,
    required Object title,
    this.cover = '',
    this.romaji,
    this.native,
    this.banner,
    this.color,
    this.format,
    this.episodes,
    this.chapters,
    this.year,
    this.status,
    this.country,
  }) : title = title is MediaTitle
            ? (title.english ?? title.romaji ?? title.userPreferred ?? '')
            : title.toString();

  final int id;
  final MediaType type;
  final String title;
  final String? romaji;
  final String? native;
  final String cover;
  final String? banner;
  final String? color;
  final String? format;
  final int? episodes;
  final int? chapters;
  final int? year;
  final MediaStatus? status;

  /// AniList `countryOfOrigin`: JP manga, KR manhwa, CN/TW manhua.
  final String? country;

  /// "Manga", "Manhwa" or "Manhua" for reading titles, "Anime" otherwise.
  String get kind => type != MediaType.manga
      ? 'Anime'
      : country == 'KR'
          ? 'Manhwa'
          : (country == 'CN' || country == 'TW')
              ? 'Manhua'
              : 'Manga';

  MediaCover get coverImage => MediaCover(large: cover, medium: cover);
  String get english => title;

  factory MediaSnapshot.fromJson(Map<String, dynamic> j) => MediaSnapshot(
    id: j.integer('id') ?? 0,
    type: _mediaTypeFromWire[j.str('type')] ?? MediaType.anime,
    title: j.str('title') ?? 'Untitled',
    romaji: j.str('romaji'),
    native: j.str('native'),
    cover: j.str('cover') ?? '',
    banner: j.str('banner'),
    color: j.str('color'),
    format: j.str('format'),
    episodes: j.integer('episodes'),
    chapters: j.integer('chapters'),
    year: j.integer('year'),
    status: j.str('status') == null ? null : _statusFromWire[j.str('status')],
    country: j.str('country'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': mediaTypeToWire(type),
    'title': title,
    if (romaji != null) 'romaji': romaji,
    if (native != null) 'native': native,
    'cover': cover,
    if (banner != null) 'banner': banner,
    if (color != null) 'color': color,
    if (format != null) 'format': format,
    if (episodes != null) 'episodes': episodes,
    if (chapters != null) 'chapters': chapters,
    if (year != null) 'year': year,
    if (status != null) 'status': status!.wire,
    if (country != null) 'country': country,
  };
}

extension MediaStatusWire on MediaStatus {
  String get wire => switch (this) {
    MediaStatus.finished => 'FINISHED',
    MediaStatus.releasing => 'RELEASING',
    MediaStatus.notYetReleased => 'NOT_YET_RELEASED',
    MediaStatus.cancelled => 'CANCELLED',
    MediaStatus.hiatus => 'HIATUS',
  };
}

class Paged<T> {
  const Paged({required this.items, required this.page, required this.hasNextPage});

  final List<T> items;
  final int page;
  final bool hasNextPage;
}

typedef CoverImage = MediaCover;
typedef NextAiringEpisode = NextAiring;

extension MediaTitleStringShim on String {
  String get english => this;
}

enum SortKey { trendingDesc, popularityDesc, scoreDesc, startDateDesc, searchMatch }

String sortKeyToWire(SortKey k) => switch (k) {
  SortKey.trendingDesc => 'TRENDING_DESC',
  SortKey.popularityDesc => 'POPULARITY_DESC',
  SortKey.scoreDesc => 'SCORE_DESC',
  SortKey.startDateDesc => 'START_DATE_DESC',
  SortKey.searchMatch => 'SEARCH_MATCH',
};

class BrowseFilters {
  const BrowseFilters({
    this.type,
    this.page = 1,
    this.perPage = 30,
    this.search,
    this.sort,
    this.genres,
    this.formats,
    this.season,
    this.year,
    this.status,
    this.country,
  });

  final MediaType? type;
  final int page;
  final int perPage;
  final String? search;
  final SortKey? sort;
  final List<String>? genres;
  final List<MediaFormat>? formats;
  final MediaSeason? season;
  final int? year;
  final MediaStatus? status;

  /// Manga only: `JP`, `KR` (manhwa), `CN` (manhua).
  final String? country;

  BrowseFilters copyWith({
    int? page,
    String? search,
    SortKey? sort,
    List<String>? genres,
    List<MediaFormat>? formats,
    MediaSeason? season,
    int? year,
    MediaStatus? status,
    String? country,
    bool clearSearch = false,
    bool clearSeason = false,
    bool clearYear = false,
    bool clearStatus = false,
    bool clearCountry = false,
  }) => BrowseFilters(
    type: type,
    page: page ?? this.page,
    perPage: perPage,
    search: clearSearch ? null : (search ?? this.search),
    sort: sort ?? this.sort,
    genres: genres ?? this.genres,
    formats: formats ?? this.formats,
    season: clearSeason ? null : (season ?? this.season),
    year: clearYear ? null : (year ?? this.year),
    status: clearStatus ? null : (status ?? this.status),
    country: clearCountry ? null : (country ?? this.country),
  );
}

/// Pulls the `media` array out of a GraphQL `Page` object.
///
/// Used by both the live queries and the on-disk feed cache, which stores the
/// raw `data` object exactly as AniList sent it — so a feed written last week
/// re-renders without the models needing their own serialiser.
List<Media> mediaListFromGql(Object? page) {
  if (page is! Map) return const [];
  final list = page['media'];
  if (list is! List) return const [];
  return [
    for (final m in list)
      if (m is Map) Media.fromJson(Map<String, dynamic>.from(m)),
  ];
}

class HomeFeed {
  const HomeFeed({required this.trending, required this.season, required this.top, required this.seasonLabel});

  final List<Media> trending;
  final List<Media> season;
  final List<Media> top;
  final ({MediaSeason season, int year}) seasonLabel;

  /// Rebuilds the three shelves straight from a saved GraphQL `data` object.
  factory HomeFeed.fromGql(Map<String, dynamic> data, ({MediaSeason season, int year}) label) => HomeFeed(
    trending: mediaListFromGql(data['trending']),
    season: mediaListFromGql(data['season']),
    top: mediaListFromGql(data['top']),
    seasonLabel: label,
  );
}

class MangaFeed {
  const MangaFeed({required this.trending, required this.manhwa, required this.top});

  final List<Media> trending;
  final List<Media> manhwa;
  final List<Media> top;

  factory MangaFeed.fromGql(Map<String, dynamic> data) => MangaFeed(
    trending: mediaListFromGql(data['trending']),
    manhwa: mediaListFromGql(data['manhwa']),
    top: mediaListFromGql(data['top']),
  );
}

class AiringItem {
  const AiringItem({required this.id, required this.episode, required this.airingAt, required this.media});

  final int id;
  final int episode;
  final int airingAt;
  final Media media;

  factory AiringItem.fromJson(Map<String, dynamic> j) => AiringItem(
    id: j.integer('id') ?? 0,
    episode: j.integer('episode') ?? 0,
    airingAt: j.integer('airingAt') ?? 0,
    media: Media.fromJson(j.obj('media') ?? const {}),
  );

  /// AniList returns the schedule as `airingSchedules`; the desktop app folds the
  /// media into each row so the grid never has to look anything up.
  factory AiringItem.fromScheduleJson(Map<String, dynamic> j) {
    final media = Media.fromJson(j.obj('media') ?? const {});
    return AiringItem(
      id: media.id,
      episode: j.integer('episode') ?? 0,
      airingAt: j.integer('airingAt') ?? 0,
      media: media,
    );
  }
}
