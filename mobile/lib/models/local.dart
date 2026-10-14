import 'json.dart';
import 'media.dart';
import 'manga.dart';
import 'stream.dart';

enum ListStatus {
  watching('watching', 'Watching'),
  planning('planning', 'Planning'),
  completed('completed', 'Completed'),
  paused('paused', 'Paused'),
  dropped('dropped', 'Dropped');

  const ListStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ListStatus parse(String? v) =>
      ListStatus.values.firstWhere((s) => s.wire == v, orElse: () => ListStatus.planning);
}

// ── Library ─────────────────────────────────────────────────────────────────

class LibraryEntry {
  const LibraryEntry({
    required this.media,
    required this.status,
    required this.addedAt,
    required this.updatedAt,
    this.categories = const [],
  });

  final MediaSnapshot media;
  final ListStatus status;
  final int addedAt;
  final int updatedAt;

  /// Mihon-style categories. A title can sit in several; empty means "Default".
  final List<String> categories;

  LibraryEntry copyWith({ListStatus? status, int? updatedAt, List<String>? categories}) => LibraryEntry(
    media: media,
    status: status ?? this.status,
    addedAt: addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    categories: categories ?? this.categories,
  );

  factory LibraryEntry.fromJson(Map<String, dynamic> j) => LibraryEntry(
    media: MediaSnapshot.fromJson(j.obj('media') ?? const {}),
    status: ListStatus.parse(j.str('status')),
    addedAt: j.integer('addedAt') ?? 0,
    updatedAt: j.integer('updatedAt') ?? 0,
    categories: j.stringList('categories') ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'status': status.wire,
    'addedAt': addedAt,
    'updatedAt': updatedAt,
    if (categories.isNotEmpty) 'categories': categories,
  };
}

class LibraryCategory {
  const LibraryCategory({required this.id, required this.name, required this.order});

  final String id;
  final String name;
  final int order;

  factory LibraryCategory.fromJson(Map<String, dynamic> j) => LibraryCategory(
    id: j.str('id') ?? 'default',
    name: j.str('name') ?? 'Default',
    order: j.integer('order') ?? 0,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};
}

class HistoryEntry {
  const HistoryEntry({
    required this.media,
    required this.episode,
    required this.position,
    required this.duration,
    required this.audio,
    required this.updatedAt,
    this.episodeTitle,
    this.thumbnail,
  });

  final MediaSnapshot media;
  final int episode;
  final String? episodeTitle;
  final String? thumbnail;
  final double position;
  final double duration;
  final Audio audio;
  final int updatedAt;

  double get fraction => duration <= 0 ? 0 : (position / duration).clamp(0.0, 1.0);

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    media: MediaSnapshot.fromJson(j.obj('media') ?? const {}),
    episode: j.integer('episode') ?? 0,
    episodeTitle: j.str('episodeTitle'),
    thumbnail: j.str('thumbnail'),
    position: j.number('position') ?? 0,
    duration: j.number('duration') ?? 0,
    audio: Audio.parse(j.str('audio')),
    updatedAt: j.integer('updatedAt') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'episode': episode,
    if (episodeTitle != null) 'episodeTitle': episodeTitle,
    if (thumbnail != null) 'thumbnail': thumbnail,
    'position': position,
    'duration': duration,
    'audio': audio.wire,
    'updatedAt': updatedAt,
  };
}

class ReadingEntry {
  const ReadingEntry({
    required this.media,
    required this.chapterId,
    required this.page,
    required this.pages,
    required this.updatedAt,
    this.chapterNumber,
    this.chapterTitle,
  });

  final MediaSnapshot media;
  final String chapterId;
  final String? chapterNumber;
  final String? chapterTitle;
  final int page;
  final int pages;
  final int updatedAt;

  factory ReadingEntry.fromJson(Map<String, dynamic> j) => ReadingEntry(
    media: MediaSnapshot.fromJson(j.obj('media') ?? const {}),
    chapterId: j.str('chapterId') ?? '',
    chapterNumber: j.str('chapterNumber'),
    chapterTitle: j.str('chapterTitle'),
    page: j.integer('page') ?? 0,
    pages: j.integer('pages') ?? 0,
    updatedAt: j.integer('updatedAt') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'chapterId': chapterId,
    if (chapterNumber != null) 'chapterNumber': chapterNumber,
    if (chapterTitle != null) 'chapterTitle': chapterTitle,
    'page': page,
    'pages': pages,
    'updatedAt': updatedAt,
  };
}

// ── Downloads ───────────────────────────────────────────────────────────────

enum DownloadState { queued, resolving, downloading, muxing, paused, done, error, cancelled }

extension DownloadStateX on DownloadState {
  String get wire => name;

  static DownloadState parse(String? v) =>
      DownloadState.values.firstWhere((s) => s.name == v, orElse: () => DownloadState.queued);

  bool get isRunning =>
      this == DownloadState.resolving || this == DownloadState.downloading || this == DownloadState.muxing;

  bool get isFinished => this == DownloadState.done || this == DownloadState.error || this == DownloadState.cancelled;

  String get label => switch (this) {
    DownloadState.queued => 'Waiting',
    DownloadState.resolving => 'Finding the stream',
    DownloadState.downloading => 'Downloading',
    DownloadState.muxing => 'Saving the file',
    DownloadState.paused => 'Paused',
    DownloadState.done => 'Done',
    DownloadState.error => 'Failed',
    DownloadState.cancelled => 'Cancelled',
  };
}

enum QualityPref { best, q1080, q720, q480, q360 }

extension QualityPrefX on QualityPref {
  String get wire => switch (this) {
    QualityPref.best => 'best',
    QualityPref.q1080 => '1080',
    QualityPref.q720 => '720',
    QualityPref.q480 => '480',
    QualityPref.q360 => '360',
  };

  String get label => switch (this) {
    QualityPref.best => 'Best available',
    QualityPref.q1080 => '1080p',
    QualityPref.q720 => '720p',
    QualityPref.q480 => '480p',
    QualityPref.q360 => '360p',
  };

  /// The ceiling handed to `ResolvedStream.pick`.
  int get maxHeight => switch (this) {
    QualityPref.best => 10000,
    QualityPref.q1080 => 1080,
    QualityPref.q720 => 720,
    QualityPref.q480 => 480,
    QualityPref.q360 => 360,
  };

  static QualityPref parse(String? v) =>
      QualityPref.values.firstWhere((q) => q.wire == v, orElse: () => QualityPref.best);
}

class EpisodeDownloadRequest {
  const EpisodeDownloadRequest({
    required this.media,
    required this.episode,
    required this.audio,
    required this.embedUrl,
    required this.quality,
    this.episodeTitle,
    this.subtitleLabel,
  });

  final MediaSnapshot media;
  final int episode;
  final String? episodeTitle;
  final Audio audio;
  final String embedUrl;
  final QualityPref quality;
  final String? subtitleLabel;

  Map<String, dynamic> toJson() => {
    'kind': 'episode',
    'media': media.toJson(),
    'episode': episode,
    if (episodeTitle != null) 'episodeTitle': episodeTitle,
    'audio': audio.wire,
    'embedUrl': embedUrl,
    'quality': quality.wire,
    if (subtitleLabel != null) 'subtitleLabel': subtitleLabel,
  };
}

class ChapterDownloadRequest {
  const ChapterDownloadRequest({required this.media, required this.chapter});

  final MediaSnapshot media;
  final Chapter chapter;

  Map<String, dynamic> toJson() => {'kind': 'chapter', 'media': media.toJson(), 'chapter': chapter.toStoreJson()};
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.kind,
    required this.media,
    required this.label,
    required this.state,
    required this.progress,
    required this.bytes,
    required this.speed,
    required this.partsDone,
    required this.partsTotal,
    required this.createdAt,
    this.episode,
    this.audio,
    this.quality,
    this.embedUrl,
    this.subtitleLabel,
    this.chapter,
    this.stage,
    this.resolution,
    this.outputFile,
    this.subtitleFile,
    this.error,
    this.finishedAt,
  });

  final String id;
  final String kind; // 'episode' | 'chapter'
  final MediaSnapshot media;

  /// `E07 · The Journey's End` / `Ch. 147 · Title`
  final String label;

  final int? episode;
  final Audio? audio;
  final QualityPref? quality;
  final String? embedUrl;
  final String? subtitleLabel;
  final Chapter? chapter;

  final DownloadState state;

  /// Free-form stage text shown under the progress bar.
  final String? stage;
  final double progress; // 0..1
  final int bytes;
  final double speed; // bytes/s, smoothed
  final int partsDone;
  final int partsTotal;
  final String? resolution;
  final String? outputFile;
  final String? subtitleFile;
  final String? error;
  final int createdAt;
  final int? finishedAt;

  bool get isEpisode => kind == 'episode';

  DownloadJob copyWith({
    DownloadState? state,
    String? stage,
    double? progress,
    int? bytes,
    double? speed,
    int? partsDone,
    int? partsTotal,
    String? resolution,
    String? outputFile,
    String? subtitleFile,
    String? error,
    int? finishedAt,
  }) => DownloadJob(
    id: id,
    kind: kind,
    media: media,
    label: label,
    episode: episode,
    audio: audio,
    quality: quality,
    embedUrl: embedUrl,
    subtitleLabel: subtitleLabel,
    chapter: chapter,
    state: state ?? this.state,
    stage: stage ?? this.stage,
    progress: progress ?? this.progress,
    bytes: bytes ?? this.bytes,
    speed: speed ?? this.speed,
    partsDone: partsDone ?? this.partsDone,
    partsTotal: partsTotal ?? this.partsTotal,
    resolution: resolution ?? this.resolution,
    outputFile: outputFile ?? this.outputFile,
    subtitleFile: subtitleFile ?? this.subtitleFile,
    error: error ?? this.error,
    createdAt: createdAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );

  factory DownloadJob.fromJson(Map<String, dynamic> j) => DownloadJob(
    id: j.str('id') ?? '',
    kind: j.str('kind') ?? 'episode',
    media: MediaSnapshot.fromJson(j.obj('media') ?? const {}),
    label: j.str('label') ?? '',
    episode: j.integer('episode'),
    audio: j.str('audio') == null ? null : Audio.parse(j.str('audio')),
    quality: j.str('quality') == null ? null : QualityPrefX.parse(j.str('quality')),
    embedUrl: j.str('embedUrl'),
    subtitleLabel: j.str('subtitleLabel'),
    chapter: j.obj('chapter') == null ? null : Chapter.fromStoreJson(j.obj('chapter')!),
    state: DownloadStateX.parse(j.str('state')),
    stage: j.str('stage'),
    progress: j.number('progress') ?? 0,
    bytes: j.integer('bytes') ?? 0,
    speed: j.number('speed') ?? 0,
    partsDone: j.integer('partsDone') ?? 0,
    partsTotal: j.integer('partsTotal') ?? 0,
    resolution: j.str('resolution'),
    outputFile: j.str('outputFile'),
    subtitleFile: j.str('subtitleFile'),
    error: j.str('error'),
    createdAt: j.integer('createdAt') ?? 0,
    finishedAt: j.integer('finishedAt'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'media': media.toJson(),
    'label': label,
    if (episode != null) 'episode': episode,
    if (audio != null) 'audio': audio!.wire,
    if (quality != null) 'quality': quality!.wire,
    if (embedUrl != null) 'embedUrl': embedUrl,
    if (subtitleLabel != null) 'subtitleLabel': subtitleLabel,
    if (chapter != null) 'chapter': chapter!.toStoreJson(),
    'state': state.wire,
    if (stage != null) 'stage': stage,
    'progress': progress,
    'bytes': bytes,
    'speed': speed,
    'partsDone': partsDone,
    'partsTotal': partsTotal,
    if (resolution != null) 'resolution': resolution,
    if (outputFile != null) 'outputFile': outputFile,
    if (subtitleFile != null) 'subtitleFile': subtitleFile,
    if (error != null) 'error': error,
    'createdAt': createdAt,
    if (finishedAt != null) 'finishedAt': finishedAt,
  };
}

/// A finished download on this device.
class OfflineItem {
  const OfflineItem({
    required this.jobId,
    required this.kind,
    required this.media,
    required this.label,
    required this.subtitles,
    required this.file,
    required this.bytes,
    required this.finishedAt,
    this.episode,
    this.chapterId,
    this.chapterNumber,
    this.quality,
    this.audio,
  });

  final String jobId;
  final String kind;
  final MediaSnapshot media;
  final String label;
  final int? episode;

  /// The provider's chapter id, so offline reading progress carries over.
  final String? chapterId;
  final String? chapterNumber;
  final String? quality;
  final Audio? audio;
  final bool subtitles;
  final String file;
  final int bytes;
  final int finishedAt;

  factory OfflineItem.fromJson(Map<String, dynamic> j) => OfflineItem(
    jobId: j.str('jobId') ?? '',
    kind: j.str('kind') ?? 'episode',
    media: MediaSnapshot.fromJson(j.obj('media') ?? const {}),
    label: j.str('label') ?? '',
    episode: j.integer('episode'),
    chapterId: j.str('chapterId'),
    chapterNumber: j.str('chapterNumber'),
    quality: j.str('quality'),
    audio: j.str('audio') == null ? null : Audio.parse(j.str('audio')),
    subtitles: j.boolean('subtitles') ?? false,
    file: j.str('file') ?? '',
    bytes: j.integer('bytes') ?? 0,
    finishedAt: j.integer('finishedAt') ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'kind': kind,
    'media': media.toJson(),
    'label': label,
    if (episode != null) 'episode': episode,
    if (chapterId != null) 'chapterId': chapterId,
    if (chapterNumber != null) 'chapterNumber': chapterNumber,
    if (quality != null) 'quality': quality,
    if (audio != null) 'audio': audio!.wire,
    'subtitles': subtitles,
    'file': file,
    'bytes': bytes,
    'finishedAt': finishedAt,
  };
}

// ── Profiles ────────────────────────────────────────────────────────────────

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.createdAt,
    this.avatar,
    this.tagline,
    this.favorites = const [],
  });

  final String id;
  final String name;

  /// Small PNG/JPEG as a data URL, kept offline.
  final String? avatar;
  final String? tagline;
  final List<MediaSnapshot> favorites;
  final int createdAt;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j.str('id') ?? '',
    name: j.str('name') ?? '',
    avatar: j.str('avatar'),
    tagline: j.str('tagline'),
    createdAt: j.integer('createdAt') ?? 0,
    favorites: [
      for (final f in j.list('favorites') ?? const [])
        if (f is Map) MediaSnapshot.fromJson(Map<String, dynamic>.from(f)),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (avatar != null) 'avatar': avatar,
    if (tagline != null) 'tagline': tagline,
    'favorites': [for (final f in favorites) f.toJson()],
    'createdAt': createdAt,
  };
}

/// What a `.playzanime` file carries when someone shares their profile.
class ProfileExport {
  const ProfileExport({
    required this.exportedAt,
    required this.profile,
    required this.library,
    required this.history,
    required this.reading,
  });

  static const String format = 'playzanime-profile';
  static const int version = 1;

  final int exportedAt;
  final Profile profile;
  final List<LibraryEntry> library;
  final List<HistoryEntry> history;
  final List<ReadingEntry> reading;

  factory ProfileExport.fromJson(Map<String, dynamic> j) {
    if (j.str('format') != format) {
      throw const ProfileFormatException('This is not a PlayzAnime profile file.');
    }
    final v = j.integer('version') ?? 0;
    if (v < 1 || v > version) {
      throw ProfileFormatException(
        v > version
            ? 'This profile was made by a newer version of PlayzAnime.'
            : 'This profile file is too old to read.',
      );
    }
    final profileJson = j.obj('profile');
    if (profileJson == null || (profileJson.str('name') ?? '').trim().isEmpty) {
      throw const ProfileFormatException('The profile has no name.');
    }
    return ProfileExport(
      exportedAt: j.integer('exportedAt') ?? 0,
      profile: Profile.fromJson(profileJson),
      library: [
        for (final e in j.list('library') ?? const [])
          if (e is Map) LibraryEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
      history: [
        for (final e in j.list('history') ?? const [])
          if (e is Map) HistoryEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
      reading: [
        for (final e in j.list('reading') ?? const [])
          if (e is Map) ReadingEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'exportedAt': exportedAt,
    'profile': profile.toJson(),
    'library': [for (final e in library) e.toJson()],
    'history': [for (final e in history) e.toJson()],
    'reading': [for (final e in reading) e.toJson()],
  };
}

class ProfileFormatException implements Exception {
  const ProfileFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Someone else's profile, imported into its own space; never mixed into ours.
class ImportedProfile {
  const ImportedProfile({required this.data, required this.importedAt});

  final ProfileExport data;
  final int importedAt;

  Profile get profile => data.profile;

  factory ImportedProfile.fromJson(Map<String, dynamic> j) => ImportedProfile(
    data: ProfileExport.fromJson(j),
    importedAt: j.integer('importedAt') ?? 0,
  );

  Map<String, dynamic> toJson() => {...data.toJson(), 'importedAt': importedAt};
}

// ── Settings ────────────────────────────────────────────────────────────────

enum PlayerMode { direct, embed }

/// How the reader lays pages out.
enum ReaderMode { vertical, paged, webtoon }

/// Which way pages advance in paged mode.
enum ReaderDirection { rtl, ltr }

enum ReaderFit { width, height, original }

class Settings {
  const Settings({
    this.accent = 'shu',
    this.titleLanguage = 'english',
    this.showNativeTitles = true,
    this.player = PlayerMode.direct,
    this.preferDub = false,
    this.autoplayNext = true,
    this.autoSkipIntro = false,
    this.quality = QualityPref.best,
    this.volume = 1,
    this.subtitleLanguage = 'English',
    this.readerMode = ReaderMode.vertical,
    this.readerDirection = ReaderDirection.rtl,
    this.readerFit = ReaderFit.width,
    this.mangaProvider = 'auto',
    this.hideAdult = true,
    this.notifyDownloads = true,
    this.dataSaver = false,
    this.autoCheckSources = true,
    this.downloadOnlyOnWifi = false,
    this.keepScreenOn = true,
    this.readerBackground = 'ink',
    this.brightness = 1,
    this.libraryLayout = 'grid',
    this.cloudflareCookie = '',
    this.cloudflareCookieHosts = '',
    this.proxyUrl = '',
    this.setupDone = false,
    this.downloadDir = '',
    this.readMode = 'strip',
    this.readerWidth = 1,
    this.subSize = 1,
    this.subColor = 'FFFFFF',
    this.subBackground = 0,
    this.subOutline = true,
    this.subBold = true,
    this.subLift = 0,
    this.seekSeconds = 5,
    this.swipeGestures = true,
    this.autoPip = true,
    this.autoRotate = true,
    this.mangaDir = '',
    this.downloadQuality = QualityPref.q720,
    this.profileName = '',
    this.profileAvatar = '',
  });

  final String accent;
  final String titleLanguage;
  final bool showNativeTitles;
  final PlayerMode player;
  final bool preferDub;
  final bool autoplayNext;
  final bool autoSkipIntro;
  final QualityPref quality;
  final double volume;
  final String subtitleLanguage;
  final ReaderMode readerMode;
  final ReaderDirection readerDirection;
  final ReaderFit readerFit;
  final String mangaProvider;
  final bool hideAdult;
  final bool notifyDownloads;
  final bool dataSaver;

  /// Ping every source on launch so the Browse list shows what is alive.
  final bool autoCheckSources;

  /// Hold downloads while on mobile data.
  final bool downloadOnlyOnWifi;

  /// Keep the display awake while a video or a chapter is open.
  final bool keepScreenOn;

  /// `ink` / `black` / `white` behind reader pages.
  final String readerBackground;

  /// Reader brightness multiplier, 0.2–1.
  final double brightness;

  /// `grid` / `list` in the Library.
  final String libraryLayout;

  /// The `cf_clearance` cookie, pasted by the user for Cloudflare-gated sites.
  final String cloudflareCookie;

  /// The hosts that cookie belongs to. A clearance cookie is issued per origin,
  /// so applying one to every source would be both useless and wrong.
  List<String> get cloudflareHosts =>
      cloudflareCookieHosts.isEmpty ? const [] : cloudflareCookieHosts.split('\n').where((h) => h.trim().isNotEmpty).toList();

  final String cloudflareCookieHosts;

  /// Optional CORS proxy prefix, used by the web build.
  final String proxyUrl;

  final bool setupDone;

  /// Folder downloads are saved to; empty means the default (Download/PlayzAnime).
  final String downloadDir;

  /// Mihon's reading modes: pagedLtr, pagedRtl, pagedVertical, strip, stripGaps.
  final String readMode;
  /// Long-strip page width as a share of the screen (side padding), 0.5–1.
  final double readerWidth;
  /// Subtitle style, applied by the built-in player and saved with downloads.
  final double subSize;
  final String subColor;
  final double subBackground;
  final bool subOutline;
  final bool subBold;
  final double subLift;
  /// Double-tap and button seek step.
  final int seekSeconds;
  final bool swipeGestures;
  final bool autoPip;
  final bool autoRotate;
  /// Folder chapters are saved to; empty means `<downloadDir>/Manga`.
  final String mangaDir;
  /// Default quality offered when downloading (smaller files than streaming 1080p).
  final QualityPref downloadQuality;
  /// Profile shown in the top bar and exported with settings.
  final String profileName;
  final String profileAvatar;

  Settings copyWith({
    String? accent,
    String? titleLanguage,
    bool? showNativeTitles,
    PlayerMode? player,
    bool? preferDub,
    bool? autoplayNext,
    bool? autoSkipIntro,
    QualityPref? quality,
    double? volume,
    String? subtitleLanguage,
    ReaderMode? readerMode,
    ReaderDirection? readerDirection,
    ReaderFit? readerFit,
    String? mangaProvider,
    bool? hideAdult,
    bool? notifyDownloads,
    bool? dataSaver,
    bool? autoCheckSources,
    bool? downloadOnlyOnWifi,
    bool? keepScreenOn,
    String? readerBackground,
    double? brightness,
    String? libraryLayout,
    String? cloudflareCookie,
    String? cloudflareCookieHosts,
    String? proxyUrl,
    bool? setupDone,
    String? downloadDir,
    String? readMode,
    double? readerWidth,
    double? subSize,
    String? subColor,
    double? subBackground,
    bool? subOutline,
    bool? subBold,
    double? subLift,
    int? seekSeconds,
    bool? swipeGestures,
    bool? autoPip,
    bool? autoRotate,
    String? mangaDir,
    QualityPref? downloadQuality,
    String? profileName,
    String? profileAvatar,
  }) => Settings(
    accent: accent ?? this.accent,
    titleLanguage: titleLanguage ?? this.titleLanguage,
    showNativeTitles: showNativeTitles ?? this.showNativeTitles,
    player: player ?? this.player,
    preferDub: preferDub ?? this.preferDub,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
    quality: quality ?? this.quality,
    volume: volume ?? this.volume,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    readerMode: readerMode ?? this.readerMode,
    readerDirection: readerDirection ?? this.readerDirection,
    readerFit: readerFit ?? this.readerFit,
    mangaProvider: mangaProvider ?? this.mangaProvider,
    hideAdult: hideAdult ?? this.hideAdult,
    notifyDownloads: notifyDownloads ?? this.notifyDownloads,
    dataSaver: dataSaver ?? this.dataSaver,
    autoCheckSources: autoCheckSources ?? this.autoCheckSources,
    downloadOnlyOnWifi: downloadOnlyOnWifi ?? this.downloadOnlyOnWifi,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    readerBackground: readerBackground ?? this.readerBackground,
    brightness: brightness ?? this.brightness,
    libraryLayout: libraryLayout ?? this.libraryLayout,
    cloudflareCookie: cloudflareCookie ?? this.cloudflareCookie,
    cloudflareCookieHosts: cloudflareCookieHosts ?? this.cloudflareCookieHosts,
    proxyUrl: proxyUrl ?? this.proxyUrl,
    setupDone: setupDone ?? this.setupDone,
    downloadDir: downloadDir ?? this.downloadDir,
    readMode: readMode ?? this.readMode,
    readerWidth: readerWidth ?? this.readerWidth,
    subSize: subSize ?? this.subSize,
    subColor: subColor ?? this.subColor,
    subBackground: subBackground ?? this.subBackground,
    subOutline: subOutline ?? this.subOutline,
    subBold: subBold ?? this.subBold,
    subLift: subLift ?? this.subLift,
    seekSeconds: seekSeconds ?? this.seekSeconds,
    swipeGestures: swipeGestures ?? this.swipeGestures,
    autoPip: autoPip ?? this.autoPip,
    autoRotate: autoRotate ?? this.autoRotate,
    mangaDir: mangaDir ?? this.mangaDir,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    profileName: profileName ?? this.profileName,
    profileAvatar: profileAvatar ?? this.profileAvatar,
  );

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    accent: j.str('accent') ?? 'shu',
    titleLanguage: j.str('titleLanguage') ?? 'english',
    showNativeTitles: j.boolean('showNativeTitles') ?? true,
    player: j.str('player') == 'embed' ? PlayerMode.embed : PlayerMode.direct,
    preferDub: j.boolean('preferDub') ?? false,
    autoplayNext: j.boolean('autoplayNext') ?? true,
    autoSkipIntro: j.boolean('autoSkipIntro') ?? false,
    quality: QualityPrefX.parse(j.str('quality')),
    volume: j.number('volume') ?? 1,
    subtitleLanguage: j.str('subtitleLanguage') ?? 'English',
    readerMode: switch (j.str('readerMode')) {
      'paged' => ReaderMode.paged,
      'webtoon' => ReaderMode.webtoon,
      _ => ReaderMode.vertical,
    },
    readerDirection: j.str('readerDirection') == 'ltr' ? ReaderDirection.ltr : ReaderDirection.rtl,
    readerFit: switch (j.str('readerFit')) {
      'height' => ReaderFit.height,
      'original' => ReaderFit.original,
      _ => ReaderFit.width,
    },
    mangaProvider: j.str('mangaProvider') ?? 'auto',
    hideAdult: j.boolean('hideAdult') ?? true,
    notifyDownloads: j.boolean('notifyDownloads') ?? true,
    dataSaver: j.boolean('dataSaver') ?? false,
    autoCheckSources: j.boolean('autoCheckSources') ?? true,
    downloadOnlyOnWifi: j.boolean('downloadOnlyOnWifi') ?? false,
    keepScreenOn: j.boolean('keepScreenOn') ?? true,
    readerBackground: j.str('readerBackground') ?? 'ink',
    brightness: j.number('brightness') ?? 1,
    libraryLayout: j.str('libraryLayout') ?? 'grid',
    cloudflareCookie: j.str('cloudflareCookie') ?? '',
    cloudflareCookieHosts: j.str('cloudflareCookieHosts') ?? '',
    proxyUrl: j.str('proxyUrl') ?? '',
    setupDone: j.boolean('setupDone') ?? false,
    downloadDir: j.str('downloadDir') ?? '',
    readMode: j.str('readMode') ?? switch (j.str('readerMode')) {
      'paged' => j.str('readerDirection') == 'ltr' ? 'pagedLtr' : 'pagedRtl',
      _ => 'strip',
    },
    readerWidth: j.number('readerWidth') ?? 1,
    subSize: j.number('subSize') ?? 1,
    subColor: j.str('subColor') ?? 'FFFFFF',
    subBackground: j.number('subBackground') ?? 0,
    subOutline: j.boolean('subOutline') ?? true,
    subBold: j.boolean('subBold') ?? true,
    subLift: j.number('subLift') ?? 0,
    seekSeconds: j.integer('seekSeconds') ?? 5,
    swipeGestures: j.boolean('swipeGestures') ?? true,
    autoPip: j.boolean('autoPip') ?? true,
    autoRotate: j.boolean('autoRotate') ?? true,
    mangaDir: j.str('mangaDir') ?? '',
    downloadQuality: j.str('downloadQuality') == null ? QualityPref.q720 : QualityPrefX.parse(j.str('downloadQuality')),
    profileName: j.str('profileName') ?? '',
    profileAvatar: j.str('profileAvatar') ?? '',
  );

  Map<String, dynamic> toJson() => {
    'accent': accent,
    'titleLanguage': titleLanguage,
    'showNativeTitles': showNativeTitles,
    'player': player.name,
    'preferDub': preferDub,
    'autoplayNext': autoplayNext,
    'autoSkipIntro': autoSkipIntro,
    'quality': quality.wire,
    'volume': volume,
    'subtitleLanguage': subtitleLanguage,
    'readerMode': readerMode.name,
    'readerDirection': readerDirection.name,
    'readerFit': readerFit.name,
    'mangaProvider': mangaProvider,
    'hideAdult': hideAdult,
    'notifyDownloads': notifyDownloads,
    'dataSaver': dataSaver,
    'autoCheckSources': autoCheckSources,
    'downloadOnlyOnWifi': downloadOnlyOnWifi,
    'keepScreenOn': keepScreenOn,
    'readerBackground': readerBackground,
    'brightness': brightness,
    'libraryLayout': libraryLayout,
    'cloudflareCookie': cloudflareCookie,
    'cloudflareCookieHosts': cloudflareCookieHosts,
    'proxyUrl': proxyUrl,
    'setupDone': setupDone,
    'downloadDir': downloadDir,
    'readMode': readMode,
    'readerWidth': readerWidth,
    'subSize': subSize,
    'subColor': subColor,
    'subBackground': subBackground,
    'subOutline': subOutline,
    'subBold': subBold,
    'subLift': subLift,
    'seekSeconds': seekSeconds,
    'swipeGestures': swipeGestures,
    'autoPip': autoPip,
    'autoRotate': autoRotate,
    'mangaDir': mangaDir,
    'downloadQuality': downloadQuality.wire,
    'profileName': profileName,
    'profileAvatar': profileAvatar,
  };
}
