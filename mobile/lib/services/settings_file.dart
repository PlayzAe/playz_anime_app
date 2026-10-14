import 'dart:async';
import 'dart:io';

import '../models/local.dart';
import 'downloader.dart';
import 'log.dart';

/// `playzanime-settings.ini`: a plain copy of the settings kept in the
/// downloads folder. Android deletes the app's own data on uninstall, but not
/// that folder, so a reinstall (or a new phone with the same SD card) picks up
/// the accent, reading mode, player and subtitle choices again. Cookies and
/// other private values never go in it.
class SettingsFile {
  SettingsFile._();

  static const fileName = 'playzanime-settings.ini';
  static const _private = {'cloudflareCookie', 'cloudflareCookieHosts', 'proxyUrl', 'setupDone', 'downloadDir', 'mangaDir', 'profileAvatar'};
  static final _log = Log('settings-file');
  static Timer? _timer;

  static String encode(Settings s) {
    final b = StringBuffer('; PlayzAnime settings. Restored automatically after a reinstall.\n[playzanime]\n');
    s.toJson().forEach((k, v) {
      if (_private.contains(k) || v == null) return;
      b.writeln('$k=${'$v'.replaceAll('\n', ' ')}');
    });
    return b.toString();
  }

  static Map<String, dynamic> decode(String text) {
    final out = <String, dynamic>{};
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#') || line.startsWith('[')) continue;
      final i = line.indexOf('=');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (_private.contains(k)) continue;
      out[k] = v == 'true'
          ? true
          : v == 'false'
              ? false
              : (num.tryParse(v) ?? v);
    }
    return out;
  }

  /// Applies an ini on top of [base], keeping the folders and private values.
  static Settings merge(Settings base, Map<String, dynamic> ini) => Settings.fromJson({...base.toJson(), ...ini});

  /// Debounced write after any settings change.
  static void schedule(Settings s) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => save(s));
  }

  static Future<void> save(Settings s) async {
    try {
      final dir = await Downloader.i.folder();
      if (!await Downloader.canWrite(dir)) return;
      await File('$dir${Platform.pathSeparator}$fileName').writeAsString(encode(s));
    } catch (e) {
      _log.warn('save failed', e);
    }
  }

  /// The ini in [dir], if a previous install left one.
  static Future<Map<String, dynamic>?> find(String dir) async {
    try {
      final f = File('$dir${Platform.pathSeparator}$fileName');
      if (!f.existsSync()) return null;
      final m = decode(await f.readAsString());
      return m.isEmpty ? null : m;
    } catch (_) {
      return null;
    }
  }
}
