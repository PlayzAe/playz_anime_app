import 'json.dart';

/// Which generic engine a source is built on.
///
/// This is the Mihon/keiyoushi model: a handful of site *templates* cover
/// hundreds of sites, so the app ships engines rather than one scraper per site.
/// `bespoke` covers the sites whose markup does not fit any template.
enum SourceEngine { madara, mangaThemesia, mangaStream, mangaBox, foolSlide, keyoapp, bespoke }

extension SourceEngineLabel on SourceEngine {
  String get label => switch (this) {
    SourceEngine.madara => 'Madara',
    SourceEngine.mangaThemesia => 'MangaThemesia',
    SourceEngine.mangaStream => 'MangaStream',
    SourceEngine.mangaBox => 'MangaBox',
    SourceEngine.foolSlide => 'FoolSlide',
    SourceEngine.keyoapp => 'Keyoapp',
    SourceEngine.bespoke => 'Custom',
  };

  String get wire => switch (this) {
    SourceEngine.madara => 'madara',
    SourceEngine.mangaThemesia => 'mangathemesia',
    SourceEngine.mangaStream => 'mangastream',
    SourceEngine.mangaBox => 'mangabox',
    SourceEngine.foolSlide => 'foolslide',
    SourceEngine.keyoapp => 'keyoapp',
    SourceEngine.bespoke => 'custom',
  };

  static SourceEngine parse(String? v) => switch (v) {
    'madara' => SourceEngine.madara,
    'mangathemesia' => SourceEngine.mangaThemesia,
    'mangastream' => SourceEngine.mangaStream,
    'mangabox' => SourceEngine.mangaBox,
    'foolslide' => SourceEngine.foolSlide,
    'keyoapp' => SourceEngine.keyoapp,
    _ => SourceEngine.bespoke,
  };
}

/// What a source is mostly for. Drives the category tabs in Browse.
enum SourceCategory { manga, manhwa, manhua, webtoon }

extension SourceCategoryLabel on SourceCategory {
  String get label => switch (this) {
    SourceCategory.manga => 'Manga',
    SourceCategory.manhwa => 'Manhwa',
    SourceCategory.manhua => 'Manhua',
    SourceCategory.webtoon => 'Webtoon',
  };

  static SourceCategory parse(String? v) => switch (v) {
    'manhwa' => SourceCategory.manhwa,
    'manhua' => SourceCategory.manhua,
    'webtoon' => SourceCategory.webtoon,
    _ => SourceCategory.manga,
  };
}

/// A source's own "browse" entry: one of its popular/latest/search results.
class SManga {
  const SManga({required this.url, required this.title, this.thumbnail, this.artist, this.author, this.description, this.genre, this.status, this.initialized = false});

  /// Site-relative or absolute URL of the series page. This is the source-scoped
  /// identity — the same series has a different `url` on every source.
  final String url;
  final String title;
  final String? thumbnail;
  final String? artist;
  final String? author;
  final String? description;
  final String? genre;
  final String? status;

  /// False until [MangaSource.details] has filled the fields in.
  final bool initialized;

  SManga copyWith({
    String? title,
    String? thumbnail,
    String? artist,
    String? author,
    String? description,
    String? genre,
    String? status,
    bool? initialized,
  }) => SManga(
    url: url,
    title: title ?? this.title,
    thumbnail: thumbnail ?? this.thumbnail,
    artist: artist ?? this.artist,
    author: author ?? this.author,
    description: description ?? this.description,
    genre: genre ?? this.genre,
    status: status ?? this.status,
    initialized: initialized ?? this.initialized,
  );
}

class SChapter {
  const SChapter({
    required this.url,
    required this.name,
    this.chapterNumber,
    this.scanlator,
    this.dateUpload,
    this.read = false,
    this.bookmark = false,
    this.lastPageRead = 0,
  });

  final String url;
  final String name;
  final String? chapterNumber;
  final String? scanlator;
  final int? dateUpload;
  final bool read;
  final bool bookmark;
  final int lastPageRead;

  SChapter copyWith({bool? read, bool? bookmark, int? lastPageRead}) => SChapter(
    url: url,
    name: name,
    chapterNumber: chapterNumber,
    scanlator: scanlator,
    dateUpload: dateUpload,
    read: read ?? this.read,
    bookmark: bookmark ?? this.bookmark,
    lastPageRead: lastPageRead ?? this.lastPageRead,
  );
}

class Page {
  const Page({required this.index, required this.url, this.imageUrl, this.uri, this.headers});

  final int index;

  /// The page URL the source handed back.
  final String url;

  /// Set when the page needs a second request to reach the real image.
  final String? imageUrl;

  final String? uri;

  /// Per-page headers some CDNs insist on (Referer, mostly).
  final Map<String, String>? headers;

  String get image => imageUrl ?? url;
}

/// A filter a source exposes in its search screen. Modelled on Mihon's
/// `FilterList` so a source can declare its own shape.
sealed class SourceFilter {
  const SourceFilter({required this.name});

  final String name;
}

class FilterText extends SourceFilter {
  const FilterText({required super.name, this.state = ''});

  final String state;

  FilterText withState(String v) => FilterText(name: name, state: v);
}

class FilterSelect extends SourceFilter {
  const FilterSelect({required super.name, required this.values, this.selected = 0});

  final List<String> values;
  final int selected;

  FilterSelect withSelected(int v) => FilterSelect(name: name, values: values, selected: v);
}

class FilterCheck extends SourceFilter {
  const FilterCheck({required super.name, this.state = false});

  final bool state;

  FilterCheck withState(bool v) => FilterCheck(name: name, state: v);
}

class FilterGroup extends SourceFilter {
  const FilterGroup({required super.name, required this.children});

  final List<SourceFilter> children;
}

/// The contract every chapter source implements. Mirrors Mihon's `Source`.
abstract class MangaSource {
  /// Stable, provider-qualified id: `mangadex`, `madara:asurascans`, …
  String get id;
  String get name;

  /// Bare origin, e.g. `https://asuratoon.com`.
  String get baseUrl;

  SourceEngine get engine;
  SourceCategory get category;

  /// Shown in the Sources list to explain what the site is good at.
  String get note;

  /// A source the user can turn off; the app still ships it.
  bool get enabled;

  /// True when the site rejects datacentre IPs or needs a browser clearance cookie.
  bool get cloudflareGated;

  /// Popular titles, 1-indexed.
  Future<List<SManga>> popular(int page);

  /// Recently updated titles, 1-indexed. May be the same as [popular].
  Future<List<SManga>> latest(int page);

  Future<List<SManga>> search(String query, int page);

  /// Filters this source exposes; empty when it has none.
  List<SourceFilter> get filters;

  /// Applies [filters] to the next [search]. Sources without filters ignore it.
  set appliedFilters(List<SourceFilter> filters);

  /// Fills in the fields [popular]/[latest]/[search] left blank.
  Future<SManga> details(SManga manga);

  Future<List<SChapter>> chapters(SManga manga);

  Future<List<Page>> pages(SChapter chapter);

  /// Cheap liveness probe used by Settings → Sources and by auto-pick.
  Future<bool> ping();
}

class MangaProviderId {
  const MangaProviderId(this.value);

  final String value;

  bool get isExtension => value.startsWith('ext:');

  @override
  bool operator ==(Object other) => other is MangaProviderId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class ProviderHealth {
  const ProviderHealth({
    required this.provider,
    required this.ok,
    required this.ms,
    required this.checkedAt,
    this.error,
  });

  final String provider;
  final bool ok;
  final int ms;
  final int checkedAt;
  final String? error;
}

/// A chapter as the app stores it. Provider-qualified id, e.g. `mangadex:uuid`.
class Chapter {
  const Chapter({
    required this.id,
    required this.provider,
    required this.name,
    this.number,
    this.title,
    this.volume,
    this.group,
    this.pages,
    this.publishedAt,
    this.externalUrl,
    this.url,
  });

  final String id;
  final String provider;

  /// The source's own label, e.g. `Chapter 12.5`.
  final String name;

  /// Chapter number as the source writes it (`12`, `12.5`); null for oneshots.
  final String? number;
  final String? title;
  final String? volume;
  final String? group;
  final int? pages;
  final int? publishedAt;

  /// Official chapters hosted elsewhere (e.g. MANGA Plus) open in the browser.
  final String? externalUrl;

  /// The source-relative chapter URL, needed to fetch pages.
  final String? url;

  /// Sort key: parses the leading number out of [name].
  double get sortKey {
    final raw = number ?? name;
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    return m == null ? -1 : (double.tryParse(m.group(1)!) ?? -1);
  }

  factory Chapter.fromStoreJson(Map<String, dynamic> j) => Chapter(
    id: j.str('id') ?? '',
    provider: j.str('provider') ?? '',
    name: j.str('name') ?? '',
    number: j.str('number'),
    title: j.str('title'),
    volume: j.str('volume'),
    group: j.str('group'),
    pages: j.integer('pages'),
    publishedAt: j.integer('publishedAt'),
    externalUrl: j.str('externalUrl'),
    url: j.str('url'),
  );

  Map<String, dynamic> toStoreJson() => {
    'id': id,
    'provider': provider,
    'name': name,
    if (number != null) 'number': number,
    if (title != null) 'title': title,
    if (volume != null) 'volume': volume,
    if (group != null) 'group': group,
    if (pages != null) 'pages': pages,
    if (publishedAt != null) 'publishedAt': publishedAt,
    if (externalUrl != null) 'externalUrl': externalUrl,
    if (url != null) 'url': url,
  };
}

class ProviderSummary {
  const ProviderSummary({
    required this.provider,
    required this.chapterCount,
    this.sourceId,
    this.title,
    this.latest,
    this.error,
  });

  final String provider;
  final String? sourceId;
  final String? title;
  final int chapterCount;
  final String? latest;
  final String? error;
}

class ChapterList {
  const ChapterList({
    required this.mediaId,
    required this.chapters,
    required this.providers,
    this.provider,
  });

  final int mediaId;

  /// The source whose chapters are in [chapters].
  final String? provider;
  final List<Chapter> chapters;

  /// Every source that was checked, with how many chapters it had.
  final List<ProviderSummary> providers;
}

class ChapterPage {
  const ChapterPage({required this.url, this.width, this.height});

  final String url;
  final int? width;
  final int? height;

  factory ChapterPage.fromJson(Map<String, dynamic> j) =>
      ChapterPage(url: j.str('url') ?? '', width: j.integer('width'), height: j.integer('height'));
}
