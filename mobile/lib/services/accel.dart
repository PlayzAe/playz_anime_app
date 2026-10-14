import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../theme/accent.dart';

/// System chrome accelerator & visual integration for hardware status bar / navigation bar.
Future<void> applyAccentToSystem(AccentKey accent) async {
  if (kIsWeb) return;
  try {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: const Color(0xFF0F0F12),
        systemNavigationBarDividerColor: accent.base.withAlpha(0x28),
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  } catch (_) {}
}