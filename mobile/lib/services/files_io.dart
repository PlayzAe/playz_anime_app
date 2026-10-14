import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the app keeps things on a real device.
///
/// The desktop build wrote to the Desktop (`Desktop\PlayzAnime`,
/// `Desktop\PlayzManga`) with a Windows-Defender fallback. A phone has no
/// equivalent the app can write to without a broad storage permission, so the
/// mobile build uses app-private storage: no permission prompt, and every file
/// is still reachable over USB and from a file manager at
/// `Android/data/tv.playzae.playzanime/files/`.
abstract final class PlatformPaths {
  static String? _root;
  static String? _externalMedia;

  /// The app-support directory. Created on first call.
  static Future<String> root() async {
    if (_root != null) return _root!;
    try {
      final base = await getApplicationSupportDirectory();
      _root = base.path;
    } catch (_) {
      // A device with no writable support dir still gets a working app.
      _root = Directory.systemTemp.path;
    }
    return _root!;
  }

  /// Public Android media directory for video files (Movies / Download).
  /// Falls back to root if external media is not accessible.
  static Future<String> mediaDir() async {
    if (_externalMedia != null) return _externalMedia!;
    if (Platform.isAndroid) {
      try {
        final movies = Directory('/storage/emulated/0/Movies');
        if (await movies.exists()) {
          _externalMedia = movies.path;
          return _externalMedia!;
        }
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
        if (extDirs != null && extDirs.isNotEmpty) {
          _externalMedia = extDirs.first.path;
          return _externalMedia!;
        }
        final downloads = Directory('/storage/emulated/0/Download');
        if (await downloads.exists()) {
          _externalMedia = downloads.path;
          return _externalMedia!;
        }
      } catch (_) {}
    }
    _externalMedia = await root();
    return _externalMedia!;
  }

  static Future<void> ensure(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) await d.create(recursive: true);
  }
}

/// Real file operations.
abstract final class Files {
  static final String sep = Platform.pathSeparator;

  static Future<bool> exists(String path) => File(path).exists();

  static Future<String?> readText(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  /// Atomic write: temp file then rename, so a crash mid-write never truncates
  /// the data. Same approach as the desktop store.
  static Future<void> writeTextAtomic(String path, String contents) async {
    final dir = Directory(path.substring(0, path.lastIndexOf(sep)));
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(path);
  }

  static Future<void> writeBytes(String path, List<int> bytes) async {
    final dir = Directory(path.substring(0, path.lastIndexOf(sep)));
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  /// Opens a file for appending, so a download can stream to disk segment by
  /// segment instead of holding an episode in memory.
  static Future<IOSink> openAppend(String path) async {
    final dir = Directory(path.substring(0, path.lastIndexOf(sep)));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(path).openWrite(mode: FileMode.writeOnlyAppend);
  }

  static Future<Uint8List?> readBytes(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  static Future<int> length(String path) async {
    final f = File(path);
    if (!await f.exists()) return 0;
    return f.length();
  }

  static Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteDir(String path) async {
    final d = Directory(path);
    if (await d.exists()) await d.delete(recursive: true);
  }

  static Future<List<String>> listFiles(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    return [
      for (final e in await d.list().toList())
        if (e is File) e.path,
    ];
  }

  /// `(path, size, modifiedAt)` for every file under [dir], recursively.
  static Future<List<({String path, int size, int at})>> walk(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <({String path, int size, int at})>[];
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final stat = await e.stat();
        out.add((path: e.path, size: stat.size, at: stat.modified.millisecondsSinceEpoch));
      }
    }
    return out;
  }

  static Future<int> dirBytes(String dir) async {
    var total = 0;
    for (final f in await walk(dir)) {
      total += f.size;
    }
    return total;
  }

  static String join(String a, String b) => a.endsWith(sep) ? '$a$b' : '$a$sep$b';

  static String parent(String path) => path.substring(0, path.lastIndexOf(sep));

  static String baseName(String path) {
    final i = path.lastIndexOf(sep);
    return i < 0 ? path : path.substring(i + 1);
  }
}
