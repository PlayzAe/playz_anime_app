import 'package:flutter/widgets.dart';

/// PlayzAnime design tokens.
///
/// Direction: a late-night screening room. Warm ink blacks (not blue-slate) so
/// poster art carries the colour, warm paper whites for text, and a single
/// accent borrowed from seal ink (shu, 朱) used only where the user acts or
/// progresses: the primary play action, progress bars, the seal mark.
///
/// Dark by design: this is a video player people use with the lights down.
///
/// Ported 1:1 from `src/renderer/styles/tokens.css`.
abstract final class Ink {
  static const ink0 = Color(0xFF0C0B0A);
  static const ink1 = Color(0xFF131210);
  static const ink2 = Color(0xFF1B1917);
  static const ink3 = Color(0xFF252220);
  static const ink4 = Color(0xFF302D2A);
}

typedef PzInk = Ink;

abstract final class Paper {
  static const paper = Color(0xFFEFE9E1);
  static const paper2 = Color(0xFFB8B1A7);
  static const paper3 = Color(0xFF8A8379);
  static const paper4 = Color(0xFF5F5952);
}

abstract final class Lines {
  /// `--line: rgb(236 229 219 / 0.08)`
  static const line = Color(0x14ECE5DB);

  /// `--line-2: rgb(236 229 219 / 0.15)`
  static const line2 = Color(0x26ECE5DB);

  /// rgb(239 233 225 / 0.something) — the paper-tinted hairlines.
  static const paper04 = Color(0x0AEFE9E1);
  static const paper08 = Color(0x14EFE9E1);
  static const paper12 = Color(0x1FEFE9E1);
  static const paper14 = Color(0x24EFE9E1);
  static const paper16 = Color(0x29EFE9E1);
  static const paper18 = Color(0x2EEFE9E1);
  static const paper20 = Color(0x33EFE9E1);
  static const paper22 = Color(0x38EFE9E1);
  static const paper25 = Color(0x40EFE9E1);
  static const paper28 = Color(0x47EFE9E1);
  static const paper30 = Color(0x4DEFE9E1);
  static const paper35 = Color(0x59EFE9E1);
  static const paper45 = Color(0x73EFE9E1);

  /// Screens and dialogs sit on a near-black wash.
  static const scrim = Color(0xA8080706); // rgb(8 7 6 / 0.66)
  static const scrimSoft = Color(0x9E080706); // 0.62
  static const scrimStrong = Color(0xD10C0B0A); // 0.82
}

abstract final class Seal {
  static const carve = Color(0xFFF6EFE4);
  static const accentInk = Color(0xFF160906);
}

abstract final class Tone {
  static const good = Color(0xFF93C48D);
  static const warn = Color(0xFFE8B85E);
  static const bad = Color(0xFFEA6B60);
}

/// `--radius-1/2/3`
abstract final class Radii {
  static const r1 = 4.0;
  static const r2 = 7.0;
  static const r3 = 12.0;

  /// Poster frames, episode thumbs, wide cards.
  static const frame = 6.0;

  /// Detail poster and hero poster.
  static const poster = 8.0;

  /// The app seal's corner ratio (9/64 at 64px).
  static const seal = 0.14;
}

/// Spacing scale. The desktop used a fixed 44px gutter; the phone shell uses a
/// smaller one but keeps the same rhythm ratios.
abstract final class Gap {
  static const g = 16.0;
  static const gutter = 16.0;
  static const gutterWide = 20.0;

  /// Vertical rhythm between shelves.
  static const shelf = 34.0;
  static const section = 40.0;

  /// Bottom padding so the last row clears the navigation bar.
  static const pageFoot = 96.0;
}

/// Motion. `--ease: cubic-bezier(0.2, 0.8, 0.2, 1)` and its named durations.
abstract final class Motion {
  static const ease = Cubic(0.2, 0.8, 0.2, 1);
  static const fast = Duration(milliseconds: 140);
  static const med = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const hero = Duration(milliseconds: 700);
}

/// The desktop type ramp, retuned for a 360-430dp viewport.
///
/// Weights map to Archivo Variable. `fontStretch` is Archivo's width axis, which
/// does the condensed display work in the original (`font-stretch: 72%`).
abstract final class Type {
  static const _family = 'Archivo';

  /// `.display` — poster and page titles.
  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.22,
    height: 0.98,
  );

  /// `.page-title` (34px on desktop → 28 on a phone).
  static const pageTitle = TextStyle(
    fontFamily: _family,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.06,
  );

  /// `.title` — general title / modal title.
  static const title = sectionTitle;

  /// `.sectionTitle` (19px).
  static const sectionTitle = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.18,
    height: 1.2,
  );

  /// `.titleSm` (16px / 600).
  static const titleSm = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
    height: 1.25,
  );


  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodySm = TextStyle(
    fontFamily: _family,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// `.poster-title` (13.5 / 600 / 1.3)
  static const posterTitle = TextStyle(
    fontFamily: _family,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// `.poster-meta` (12 / paper-3)
  static const posterMeta = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  /// Buttons.
  static const button = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  static const buttonSm = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  static const buttonLg = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );
}

/// Every value the desktop kept in CSS that the phone layout still honours.
abstract final class Metrics {
  /// Bottom navigation bar height, excluding the safe-area inset.
  static const navBar = 58.0;

  /// The compact app bar that replaces the desktop title bar.
  static const appBar = 52.0;

  /// `.poster-grid` — `minmax(156px, 1fr)` with a 30/18 gap. On a phone the
  /// equivalent is three columns at a 360dp width.
  static const posterMin = 104.0;
  static const posterGapX = 12.0;
  static const posterGapY = 20.0;

  /// `.shelf-track` — `grid-auto-columns: 162px`, gap 18.
  static const shelfCard = 124.0;
  static const shelfCardWide = 240.0;
  static const shelfGap = 12.0;

  /// `.ep-thumb` is 16/9; the card grid is `minmax(236px, 1fr)`.
  static const epMin = 168.0;

  /// Poster art is always 460/650.
  static const posterAspect = 460 / 650;
}
