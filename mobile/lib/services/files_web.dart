import 'package:flutter/foundation.dart';

/// The browser stand-in for the file layer.
///
/// A Flutter web build has no file system: downloads are handed to the browser,
/// the store lives in `localStorage`, and the image cache is the browser's own.
/// Every method here is a well-defined no-op rather than a throw, so the shared
/// code paths do not need a web branch at every call site.
abstract final class PlatformPaths {
  static Future<String> root() async => '';

  static Future<String> mediaDir() async => '';

  static Future<void> ensure(String dir) async {}
}

abstract final class Files {
  static final String sep = '/';

  static Future<bool> exists(String path) async => false;

  static Future<String?> readText(String path) async => null;

  static Future<void> writeTextAtomic(String path, String contents) async {}

  static Future<void> writeBytes(String path, List<int> bytes) async {}

  /// Nothing to append to. The download engine checks `kIsWeb` and hands the
  /// file to the browser instead of calling this.
  static Future<Never> openAppend(String path) async {
    throw UnsupportedError('A browser tab cannot write files; use the browser download path.');
  }

  static Future<Uint8List?> readBytes(String path) async => null;

  static Future<int> length(String path) async => 0;

  static Future<void> delete(String path) async {}

  static Future<void> deleteDir(String path) async {}

  static Future<List<String>> listFiles(String dir) async => const [];

  static Future<List<({String path, int size, int at})>> walk(String dir) async => const [];

  static Future<int> dirBytes(String dir) async => 0;

  static String join(String a, String b) => a.isEmpty ? b : '$a/$b';

  static String parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String baseName(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  /// Debug-only, so an accidental call stands out.
  static void warn(String what) {
    if (kDebugMode) debugPrint('files_web: $what');
  }
}
