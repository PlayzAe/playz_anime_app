import 'package:flutter/foundation.dart';

import 'files.dart';
import 'log.dart';

/// Where the app keeps things.
///
/// Mirrors the desktop build's `Desktop\PlayzAnime` and `Desktop\PlayzManga`
/// layout inside app-private storage, so a downloaded episode lands at
/// `…/downloads/anime/<Show>/Season 2/<Show>_E05_720p.ts` and a chapter at
/// `…/downloads/manga/<Series>/<Series>_Ch012.cbz` — the same shape the README
/// documents, just somewhere a phone will actually let us write.
///
/// All the platform-specific work is behind [Files], so this file compiles for
/// web as well.
class Paths {
  Paths._();

  static final Paths i = Paths._();
  final _log = Log('paths');

  String? _root;
  String? _mediaRoot;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    if (kIsWeb) {
      _root = '';
      _mediaRoot = '';
      _ready = true;
      return;
    }
    try {
      final base = await PlatformPaths.root();
      _root = base;
      final mediaBase = await PlatformPaths.mediaDir();
      _mediaRoot = mediaBase;
      await PlatformPaths.ensure(animeDir);
      await PlatformPaths.ensure(mangaDir);
      await PlatformPaths.ensure(imageCacheDir);
      await PlatformPaths.ensure(tempDir);
    } catch (err) {
      _log.error('could not prepare app directories', err);
      _root = '';
    }
    _ready = true;
  }

  String get root => _root ?? '';
  String get mediaRoot => _mediaRoot ?? root;

  String get dataFile => _join(root, 'playzanime-data.json');

  String get feedCacheFile => _join(root, 'feed-cache.json');

  /// Downloaded episodes. Saved in user-accessible storage (Movies/PlayzAnime) so Android players & gallery find them.
  String get animeDir => _join(mediaRoot, 'PlayzAnime');

  /// Downloaded chapters. Saved in user-accessible storage (PlayzManga).
  String get mangaDir => _join(mediaRoot, 'PlayzManga');

  String get downloadsDir => animeDir;

  String get imageCacheDir => _join(root, 'cache/images');

  String get tempDir => _join(root, 'tmp');

  static String _join(String a, String b) => a.isEmpty ? b : Files.join(a, b);

  /// `…/anime/<Show>/Season 2/<Show>_E05_720p.ts`
  ///
  /// The extension is usually `ts`: the mobile downloader concatenates the HLS
  /// transport stream rather than remuxing it, because shipping ffmpeg would
  /// add 15-30 MB per ABI to the APK. ExoPlayer and VLC both play it, and the
  /// player screen does not care what the file is called.
  String episodeFile({
    required String show,
    required int episode,
    required String quality,
    String? season,
    String extension = 'ts',
  }) {
    final folder = season == null ? _join(animeDir, show) : _join(_join(animeDir, show), season);
    final n = episode.toString().padLeft(2, '0');
    final safeQuality = quality.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    return _join(folder, '${show}_E${n}_${safeQuality.isEmpty ? 'auto' : safeQuality}.$extension');
  }

  /// `…/manga/<Series>/<Series>_Ch012.cbz`
  String chapterFile({required String series, required String chapterNumber, String extension = 'cbz'}) {
    final clean = chapterNumber.replaceAll(RegExp(r'[^\d.]'), '');
    final padded = clean.isEmpty
        ? '000'
        : clean.contains('.')
        ? '${clean.split('.').first.padLeft(3, '0')}.${clean.split('.').last}'
        : clean.padLeft(3, '0');
    return _join(_join(mangaDir, series), '${series}_Ch$padded.$extension');
  }

  /// The page cache for one chapter that is being read online.
  String chapterPageCacheDir(String provider, String chapterId) {
    final safe = chapterId.replaceAll(RegExp(r'[^0-9a-zA-Z._-]'), '_');
    return _join(_join(imageCacheDir, provider), safe);
  }

  String subtitleFile(String videoPath, [String extension = 'vtt']) {
    final dot = videoPath.lastIndexOf('.');
    return dot < 0 ? '$videoPath.$extension' : '${videoPath.substring(0, dot)}.$extension';
  }

  Future<void> ensureParent(String filePath) async {
    if (kIsWeb || filePath.isEmpty) return;
    await PlatformPaths.ensure(Files.parent(filePath));
  }

  /// Frees the image cache when it grows past [maxBytes].
  ///
  /// The desktop build let Chromium manage this. On a phone the app owns the
  /// directory, and an unbounded cache of 200 KB webtoon pages adds up fast.
  /// Oldest first, so the pages the reader is most likely to want again stay.
  Future<int> trimImageCache({int maxBytes = 200 * 1024 * 1024}) async {
    if (kIsWeb) return 0;
    try {
      final entries = await Files.walk(imageCacheDir);
      var total = 0;
      for (final e in entries) {
        total += e.size;
      }
      if (total <= maxBytes) return 0;

      final sorted = [...entries]..sort((a, b) => a.at.compareTo(b.at));
      var freed = 0;
      for (final e in sorted) {
        if (total - freed <= maxBytes) break;
        await Files.delete(e.path);
        freed += e.size;
      }
      _log.info('trimmed image cache, freed ${freed ~/ 1024} KB');
      return freed;
    } catch (err) {
      _log.warn('image cache trim failed', err);
      return 0;
    }
  }

  Future<int> imageCacheBytes() => kIsWeb ? Future.value(0) : Files.dirBytes(imageCacheDir);

  /// Total size of everything under `downloads/`.
  Future<int> downloadsBytes() => kIsWeb ? Future.value(0) : Files.dirBytes(downloadsDir);
}
