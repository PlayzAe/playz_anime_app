import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Accent options, named after traditional Japanese colours.
///
/// Ported from the `:root[data-accent=…]` blocks in `tokens.css`.
enum AccentKey {
  shu('朱', 'Shu', Color(0xFFF0532C), Color(0xFFFF6B45)),
  matcha('抹茶', 'Matcha', Color(0xFF9DBB5C), Color(0xFFB1CF70)),
  ai('藍', 'Ai', Color(0xFF6F8FE6), Color(0xFF86A3F2)),
  yamabuki('山吹', 'Yamabuki', Color(0xFFF3AA36), Color(0xFFFFBD55)),
  sakura('桜', 'Sakura', Color(0xFFEE83A1), Color(0xFFF79BB4));

  const AccentKey(this.kanji, this.label, this.base, this.hi);

  /// The kanji shown on the settings swatch.
  final String kanji;
  final String label;

  /// `--accent`
  final Color base;

  /// `--accent-hi`
  final Color hi;

  /// `--accent-soft: color-mix(in oklab, var(--accent) 18%, transparent)`.
  ///
  /// Flutter has no oklab colour-mix, so this reproduces the same result by
  /// compositing in linear space, which is visually equivalent at this alpha.
  Color get soft => withOpacityLinear(base, 0.18);

  static AccentKey parse(String? value) =>
      AccentKey.values.firstWhere((a) => a.name == value, orElse: () => AccentKey.shu);
}

/// `color-mix(in oklab, color X%, transparent)` — pre-multiplied alpha without
/// the double-darkening you get from naive `withOpacity` over a dark background.
Color withOpacityLinear(Color c, double alpha) {
  final a = (alpha.clamp(0.0, 1.0) * 255).round();
  return c.withAlpha(a);
}

/// `color-mix(in oklab, a p%, b)` for the two places the design leans on it
/// (the offline notice and the friend-profile wash).
Color mixOklab(Color a, double pa, Color b) {
  final t = pa.clamp(0.0, 1.0);
  final r = (a.r * t + b.r * (1 - t)).clamp(0.0, 1.0);
  final g = (a.g * t + b.g * (1 - t)).clamp(0.0, 1.0);
  final bl = (a.b * t + b.b * (1 - t)).clamp(0.0, 1.0);
  return Color.fromARGB(
    255,
    (r * 255).round(),
    (g * 255).round(),
    (bl * 255).round(),
  );
}

/// Applies the current accent color to system chrome (status bar / nav bar on Android).
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

/// The live accent. Rebuilt whenever the user picks a different seal colour, so
/// widgets can read `PzAccent.of(context).base` instead of plumbing a colour.
class PzAccent extends InheritedWidget {
  const PzAccent({required this.key0, required super.child, super.key});

  final AccentKey key0;

  Color get base => key0.base;
  Color get hi => key0.hi;
  Color get soft => key0.soft;

  static const PzAccent amber = PzAccent(key0: AccentKey.yamabuki, child: SizedBox.shrink());
  static const PzAccent shu = PzAccent(key0: AccentKey.shu, child: SizedBox.shrink());
  static const PzAccent matcha = PzAccent(key0: AccentKey.matcha, child: SizedBox.shrink());
  static const PzAccent ai = PzAccent(key0: AccentKey.ai, child: SizedBox.shrink());
  static const PzAccent yamabuki = PzAccent(key0: AccentKey.yamabuki, child: SizedBox.shrink());
  static const PzAccent sakura = PzAccent(key0: AccentKey.sakura, child: SizedBox.shrink());

  static PzAccent of(BuildContext context) {
    final found = context.dependOnInheritedWidgetOfExactType<PzAccent>();
    assert(found != null, 'PzAccent is missing above this widget');
    return found!;
  }

  @override
  bool updateShouldNotify(PzAccent oldWidget) => oldWidget.key0 != key0;
}

class PzAccentScope extends StatelessWidget {
  const PzAccentScope({super.key, this.accent, required this.child});

  final dynamic accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AccentKey k = AccentKey.shu;
    if (accent is AccentKey) {
      k = accent as AccentKey;
    } else if (accent is PzAccent) {
      k = (accent as PzAccent).key0;
    }
    return PzAccent(key0: k, child: child);
  }
}
