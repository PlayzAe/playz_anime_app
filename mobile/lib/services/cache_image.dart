import 'dart:async';

import 'package:file/file.dart' as f; // ignore: depend_on_referenced_packages
import 'package:file/local.dart'; // ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
// flutter_cache_manager is a transitive dependency of cached_network_image —
// the types are needed here directly to point the store at our own directory.
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; // ignore: depend_on_referenced_packages

import 'log.dart';
import 'paths.dart';

/// Artwork on disk: AniList covers and banners, episode stills, manga pages.
///
/// Chromium ran this on the desktop and we never saw it. On a phone the app
/// owns the directory, and it has to stay under [Paths.imageCacheDir] so
/// `Paths.trimImageCache()` can ring-fence the space — a 460x650 cover is
/// around 120KB and one browse session touches a few hundred of them.
///
/// Two callers share one directory: [get] for "do we already have this file"
/// (prefetch checks, the profiles screen, the offline notice) and the
/// [cacheManager] handle `cached_network_image` fetches through. Both read and
/// write the same files, so there is never a second copy of an image.
class ImageCacheManager {
  ImageCacheManager._();

  static final ImageCacheManager i = ImageCacheManager._();

  /// The disk budget. Larger than a photo app's, smaller than the download
  /// folders: artwork is disposable, downloads are not.
  static const int budgetBytes = 200 * 1024 * 1024;

  /// The README's promise in plain numbers — "artwork is cached on disk for a
  /// month, so revisiting a page costs nothing".
  static const Duration ttl = Duration(days: 30);

  /// A byte budget is the real bound; this is the second net for the
  /// pathological case of tens of thousands of tiny covers, where the
  /// directory stays small but the index does not.
  static const int _maxObjects = 1600;

  static const String _key = 'playzanime-artwork';

  final _log = Log('image-cache');

  BaseCacheManager? _manager;
  bool _swept = false;

  /// The handle `cached_network_image` wants.
  ///
  /// Built lazily: it opens an index file, and a first frame that shows no
  /// image should not pay for that.
  BaseCacheManager get cacheManager => _manager ??= _build();

  BaseCacheManager _build() {
    // The web build leans on the browser's own HTTP cache. There is no
    // directory to own, no index to keep, and `dart:io` cannot back either.
    if (kIsWeb) {
      return CacheManager(Config(_key, stalePeriod: ttl, maxNrOfCacheObjects: _maxObjects));
    }
    return CacheManager(
      Config(
        _key,
        stalePeriod: ttl,
        maxNrOfCacheObjects: _maxObjects,
        // The default repository on Android is sqflite-backed; JSON is one
        // less native plugin in the app for a table of URLs and timestamps.
        repo: JsonCacheInfoRepository(databaseName: _key),
        fileSystem: const _ArtworkFiles(),
      ),
    );
  }

  /// The cached file for [url], or null when it is missing or past [ttl].
  ///
  /// Never throws. A dead cache is a missing image, not a broken screen.
  Future<f.File?> get(String url) async {
    if (url.isEmpty || kIsWeb) return null;
    _sweepOnce();
    try {
      final file = (await cacheManager.getFileFromCache(url))?.file;
      if (file == null || !await file.exists()) return null;

      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age > ttl) {
        // Drop the index entry along with the file, or the next lookup finds
        // a record pointing at nothing.
        await cacheManager.removeFile(url);
        return null;
      }
      // `Paths.trimImageCache()` evicts oldest-first by mtime, so a hit has to
      // count as a touch — otherwise a cover you open every day is evicted
      // before one you saw once last Tuesday.
      if (age > const Duration(minutes: 10)) await file.setLastModified(DateTime.now());
      return file;
    } catch (err) {
      _log.warn('artwork lookup failed', err);
      return null;
    }
  }

  /// Brings the directory back under [budgetBytes], oldest first.
  ///
  /// Settings calls it, and [get] runs one sweep after launch so the cache
  /// self-limits without anyone remembering to press a button.
  Future<void> trim() async {
    try {
      await Paths.i.trimImageCache(maxBytes: budgetBytes);
    } catch (err) {
      _log.warn('artwork trim failed', err);
    }
  }

  /// The sweep runs on the first image request rather than at boot, so app
  /// start is not waiting on a directory walk.
  void _sweepOnce() {
    if (_swept) return;
    _swept = true;
    // Deliberately not awaited: the caller wants an image, not a disk walk.
    unawaited(trim());
  }
}

/// Writes every cached image into [Paths.imageCacheDir], under a hash of the
/// name the cache store derives from the URL.
///
/// The store's own file system parks files in the OS temp directory, which
/// Android may clear at will and which `trimImageCache` cannot see. This one
/// keeps the app's promise: one directory, one budget, one sweeper.
class _ArtworkFiles implements FileSystem {
  const _ArtworkFiles();

  @override
  Future<f.File> createFile(String name) async {
    const fs = LocalFileSystem();
    final dir = fs.directory(Paths.i.imageCacheDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.childFile('${_hash(name)}.img');
  }
}

/// Two 32-bit FNV-1a lanes over the URL — 64 bits of hash, no dependency, and
/// stable across launches.
///
/// Stability is the whole point: `String.hashCode` is salted per isolate, so a
/// filename built from it would change every time the app started and the disk
/// cache would be dead weight.
String _hash(String value) {
  var h1 = 0x811c9dc5;
  var h2 = 0x9e3779b9;
  for (final unit in value.codeUnits) {
    h1 = ((h1 ^ unit) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ unit) * 0x85ebca6b) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
}
