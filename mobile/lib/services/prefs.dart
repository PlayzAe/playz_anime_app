import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A thin JSON wrapper over `SharedPreferences`.
///
/// Two jobs: the web build has no file system, so the small bits of state that
/// must survive a reload (settings, library) live here instead; and on Android
/// the cookie jar is kept here too, because it is small and read on every request.
class Prefs {
  Prefs._();

  static final Prefs i = Prefs._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> setJson(String key, Object? value) async {
    await init();
    if (value == null) {
      await _prefs!.remove(key);
    } else {
      await _prefs!.setString(key, jsonEncode(value));
    }
  }

  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (err) {
      debugPrint('prefs: could not parse $key ($err)');
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    await init();
    await _prefs!.setString(key, value);
  }

  String? getString(String key) => _prefs?.getString(key);

  Future<void> setBool(String key, bool value) async {
    await init();
    await _prefs!.setBool(key, value);
  }

  bool getBool(String key, {bool fallback = false}) => _prefs?.getBool(key) ?? fallback;

  Future<void> setInt(String key, int value) async {
    await init();
    await _prefs!.setInt(key, value);
  }

  int getInt(String key, {int fallback = 0}) => _prefs?.getInt(key) ?? fallback;

  Future<void> remove(String key) async {
    await init();
    await _prefs!.remove(key);
  }

  Future<void> clear() async {
    await init();
    await _prefs!.clear();
  }
}
