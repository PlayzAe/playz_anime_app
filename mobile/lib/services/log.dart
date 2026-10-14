import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Tiny structured logger, the same shape as `src/main/log.ts`.
///
/// Nothing is written to disk: a phone has limited patience for log files, and
/// the console output is enough to debug a source that broke. Release builds
/// keep only warnings and errors.
enum LogLevel { debug, info, warn, error }

class Log {
  Log(this.scope);

  final String scope;

  static LogLevel minLevel = kReleaseMode ? LogLevel.warn : LogLevel.debug;

  static final List<String> _recent = <String>[];
  static const int _recentMax = 200;

  /// The last lines logged, for the "what went wrong" panel in Settings.
  static List<String> get recent => List.unmodifiable(_recent);

  void _emit(LogLevel level, String message, [Object? error]) {
    if (level.index < minLevel.index) return;
    final line = '[$scope] $message${error == null ? '' : ' — $error'}';
    _recent.add(line);
    if (_recent.length > _recentMax) _recent.removeRange(0, _recent.length - _recentMax);
    if (!kReleaseMode) {
      dev.log(line, name: scope, level: _levelOf(level));
      debugPrint(line);
    }
  }

  static int _levelOf(LogLevel l) => switch (l) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warn => 900,
    LogLevel.error => 1000,
  };

  void debug(String m, [Object? e]) => _emit(LogLevel.debug, m, e);
  void info(String m, [Object? e]) => _emit(LogLevel.info, m, e);
  void warn(String m, [Object? e]) => _emit(LogLevel.warn, m, e);
  void error(String m, [Object? e]) => _emit(LogLevel.error, m, e);
}
