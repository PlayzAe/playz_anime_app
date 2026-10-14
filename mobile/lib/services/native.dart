import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android side of PlayzAnime (`MainActivity.kt`): the Mihon extension host,
/// launcher icon, picture-in-picture, brightness/volume, permissions and
/// notifications. Every call is a no-op off Android so tests and desktop runs work.
class Native {
  Native._();

  static const _ext = MethodChannel('playz/ext');
  static const _sys = MethodChannel('playz/system');

  static bool get available => !kIsWeb && Platform.isAndroid;

  /// `pip` (bool) and `permissions` (map) events from the activity.
  static final pip = ValueNotifier<bool>(false);
  static final permissions = ValueNotifier<Map<String, bool>>(const {});

  /// Media buttons: play, pause, next, back, forward.
  static final media = StreamController<String>.broadcast();

  static bool _wired = false;
  static void wire() {
    if (_wired || !available) return;
    _wired = true;
    _sys.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pip':
          pip.value = call.arguments == true;
        case 'permissions':
          permissions.value = Map<String, bool>.from(call.arguments as Map);
        case 'media':
          media.add('${call.arguments}');
      }
      return null;
    });
  }

  // ── Extensions ──────────────────────────────────────────────────────────

  static Future<T> ext<T>(String method, [Map<String, Object?> args = const {}]) async {
    if (!available) throw StateError('Extensions run on Android only.');
    try {
      return await _ext.invokeMethod<T>(method, args) as T;
    } on PlatformException catch (e) {
      throw ExtensionError(e.message ?? e.code);
    }
  }

  // ── System ──────────────────────────────────────────────────────────────

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (!available) return null;
    try {
      return await _sys.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setIcon(String accent) => _call('setIcon', {'accent': accent});

  static Future<bool> pipSupported() async => await _call<bool>('pipSupported') ?? false;
  static Future<bool> enterPip() async => await _call<bool>('pip') ?? false;
  static Future<void> armPip(bool on, {int w = 16, int h = 9}) => _call('armPip', {'on': on, 'w': w, 'h': h});

  static Future<double> brightness() async => await _call<double>('getBrightness') ?? 0.5;
  static Future<void> setBrightness(double v) => _call('setBrightness', {'value': v});
  static Future<double> volume() async => await _call<double>('getVolume') ?? 0.5;
  static Future<void> setVolume(double v) => _call('setVolume', {'value': v});

  static Future<Map<String, bool>> permissionState() async {
    final m = await _call<Map>('permissions');
    final out = m == null ? const {'notifications': true, 'files': true} : Map<String, bool>.from(m);
    permissions.value = out;
    return out;
  }

  static Future<void> requestNotifications() => _call('requestNotifications');
  static Future<void> requestFiles() => _call('requestFiles');
  static Future<void> openAppSettings() => _call('openAppSettings');

  static Future<void> downloadProgress({required String title, required String text, required int percent, required int active}) =>
      _call('downloadProgress', {'title': title, 'text': text, 'percent': percent, 'active': active});
  static Future<void> downloadDone({String? title, String? text}) => _call('downloadDone', {'title': title, 'text': text});

  static Future<void> nowPlaying({required String title, required String text, required bool playing, required bool hasNext}) =>
      _call('nowPlaying', {'title': title, 'text': text, 'playing': playing, 'hasNext': hasNext});
  static Future<void> stopPlaying() => _call('stopPlaying');
}

class ExtensionError implements Exception {
  ExtensionError(this.message);
  final String message;
  @override
  String toString() => message;
}
