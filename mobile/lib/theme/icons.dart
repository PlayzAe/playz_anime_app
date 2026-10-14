/// PlayzAnime's own icon set, drawn on a 24px grid.
///
/// The rules that make it ours: square caps and mitred joins (no soft rounded
/// strokes), and most icons carry one solid block — a door, a poster, a knob —
/// that anchors the glyph.
///
/// Ported verbatim from `src/renderer/components/Icon.tsx`. The bodies live as
/// SVG fragments and are compiled to `ui.Path` once, lazily, by [buildGlyph].
library;

/// Stroked path at the icon's default width.
String _s(String d) => '<path d="$d"/>';

/// Solid path: the anchor block.
String _f(String d) => '<path d="$d" fill="currentColor" stroke="none"/>';

/// Solid rect, same job as [_f] but with a rectangle.
String _r(double x, double y, double w, double h) =>
    '<rect x="$x" y="$y" width="$w" height="$h" fill="currentColor" stroke="none"/>';

/// Outline rect: stroked, no fill.
String _o(double x, double y, double w, double h, [double? r]) =>
    '<rect x="$x" y="$y" width="$w" height="$h"${r == null ? '' : ' rx="$r"'}/>';

String _c(double cx, double cy, double r) => '<circle cx="$cx" cy="$cy" r="$r"/>';

const Map<String, String> _rawGlyphs = <String, String>{};

/// Name → SVG fragment. Mirrors the `glyphs` record in `Icon.tsx` one-for-one.
final Map<String, String> glyphBodies = <String, String>{
  'home': _s('M3.5 11 12 4l8.5 7') + _s('M5.5 9.5V20.5h13V9.5') + _r(10, 14, 4, 6.5),
  'heart':
      _s('M12 20 4.2 12.4A4.6 4.6 0 0 1 12 6.6a4.6 4.6 0 0 1 7.8 5.8z') +
          _f('M12 20 4.2 12.4A4.6 4.6 0 0 1 12 6.6z'),
  'tv': _o(3.5, 6.5, 17, 13) + _s('M8.5 3 12 6.5 15.5 3') + _f('M10 10.2v6l5-3z'),
  'manga':
      _s('M12 6.5C9 4.6 6.4 4.4 3.5 5.3v13.4c2.9-.9 5.5-.7 8.5 1.2') +
          _f('M12 6.5c3-1.9 5.6-2.1 8.5-1.2v13.4c-2.9-.9-5.5-.7-8.5 1.2z'),
  'discover':
      _o(3.5, 3.5, 7, 10) + _r(13, 3, 8, 7) + _o(3.5, 16.5, 7, 4) + _o(13.5, 13, 7, 7.5),
  'schedule': _o(3.5, 5.5, 17, 15) + _s('M3.5 10h17') + _s('M8 3v4M16 3v4') + _r(13, 13.5, 4, 4),
  'library':
      _s('M8 7H4.5v13.5h11V18') + _o(8, 3.5, 12, 14.5) + _f('M11.5 3.5h5v8l-2.5-1.9-2.5 1.9z'),
  'downloads': _s('M12 3.5v8') + _f('M7.5 10 12 15l4.5-5z') + _s('M4 15.5v5h16v-5'),
  'search': '${_c(10.5, 10.5, 6.25)}<path d="m15.25 15.25 5 5" stroke-width="2.6"/>',
  'settings': _s('M3.5 7.5h17M3.5 16.5h17') + _r(6.5, 4.75, 4.5, 5.5) + _r(13, 13.75, 4.5, 5.5),
  'history':
      _s('M4.7 13.5A7.5 7.5 0 1 0 6.6 6.8') + _f('M3.5 3.5v5.5H9z') + _s('M12 8v4.5l3 2'),
  'play': _f('M6.5 4v16l13-8z'),
  'pause': _r(6, 4.5, 4, 15) + _r(14, 4.5, 4, 15),
  'next': _f('M5 5v14l10-7z') + _r(16.5, 5, 2.5, 14),
  'prev': _f('M19 5v14L9 12z') + _r(5, 5, 2.5, 14),
  'back10':
      '${_s('M5.2 13.5A7 7 0 1 0 7.2 7')}'
      '${_f('M4 3.8v5.4h5.4z')}'
      '<text x="12.4" y="15.6" font-size="6.8" font-weight="700">10</text>',
  'fwd10':
      '${_s('M18.8 13.5A7 7 0 1 1 16.8 7')}'
      '${_f('M20 3.8v5.4h-5.4z')}'
      '<text x="11.6" y="15.6" font-size="6.8" font-weight="700">10</text>',
  'back5':
      '${_s('M5.2 13.5A7 7 0 1 0 7.2 7')}'
      '${_f('M4 3.8v5.4h5.4z')}'
      '<text x="10.2" y="16" font-size="7.4" font-weight="700">5</text>',
  'fwd5':
      '${_s('M18.8 13.5A7 7 0 1 1 16.8 7')}'
      '${_f('M20 3.8v5.4h-5.4z')}'
      '<text x="10.2" y="16" font-size="7.4" font-weight="700">5</text>',
  'sun': _c(12, 12, 3.6) + _s('M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1'),
  'lock': _o(5, 10.5, 14, 10) + _s('M8 10.5V7.5a4 4 0 0 1 8 0v3') + _r(11, 14, 2, 3.5),
  'rotate': _s('M4.5 12a7.5 7.5 0 0 1 13-5.1') + _f('M19.5 3.5v5.5H14z') + _s('M19.5 12a7.5 7.5 0 0 1-13 5.1') + _f('M4.5 20.5V15H10z'),
  'volume':
      _f('M3.5 9h3.8L12 5v14l-4.7-4H3.5z') +
          _s('M15.5 9a4.2 4.2 0 0 1 0 6') +
          _s('M18 6.5a7.8 7.8 0 0 1 0 11'),
  'volumeLow': _f('M3.5 9h3.8L12 5v14l-4.7-4H3.5z') + _s('M15.5 9a4.2 4.2 0 0 1 0 6'),
  'mute': _f('M3.5 9h3.8L12 5v14l-4.7-4H3.5z') + _s('m15.5 9.5 5 5M20.5 9.5l-5 5'),
  'fullscreen': _s('M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5'),
  'fullscreenExit': _s('M9 4v5H4M20 9h-5V4M15 20v-5h5M4 15h5v5'),
  'pip': _o(3.5, 5.5, 17, 13) + _r(12, 12, 7, 5),
  'subtitles': _o(3.5, 5.5, 17, 13) + _s('M7 11.5h3.5M13 11.5h4M7 15h6.5M16 15h1'),
  'theater': _o(2.5, 6.5, 19, 11) + _r(2.5, 15.5, 19, 2),
  'skip': _s('M5 6l6 6-6 6M12.5 6l6 6-6 6'),
  'speed': _s('M4.2 16.5A8.5 8.5 0 1 1 19.8 16.5') + _f('M11 12.8 16.5 8l-3.7 6.3z'),
  'arrowLeft': _s('M20 12H5M11 5.5 4.5 12l6.5 6.5'),
  'arrowRight': _s('M4 12h15M13 5.5l6.5 6.5-6.5 6.5'),
  'chevronLeft': _s('M14.5 5.5 8 12l6.5 6.5'),
  'chevronRight': _s('M9.5 5.5 16 12l-6.5 6.5'),
  // Defined twice in the original object literal; the later one wins in JS.
  'chevronDown': _s('M6 9l6 6 6-6'),
  'close': _s('M6 6l12 12M18 6 6 18'),
  'check': _s('M4.5 12.5 9.5 17.5 19.5 6.5'),
  'plus': _s('M12 4.5v15M4.5 12h15'),
  'minus': _s('M4.5 12h15'),
  'bookmark': _s('M6.5 3.5h11v17l-5.5-4-5.5 4z'),
  'bookmarkFilled': _f('M6 3h12v18l-6-4.4L6 21z'),
  'folder': _s('M3.5 6h6l2 2.5h9v11h-17z'),
  'external': _s('M13.5 4.5h6v6M19.5 4.5l-8 8M17 14v5.5H4.5V7H10'),
  'trash': _s('M4.5 6.5h15M9.5 6.5V4h5v2.5M6.5 6.5l1 14h9l1-14'),
  'refresh': _s('M19.3 10.5A7.5 7.5 0 1 0 17.4 17') + _f('M20.5 4v5.5H15z'),
  'info': _c(12, 12, 8.5) + _s('M12 11v6') + _r(11, 7, 2, 2),
  'alert': _s('M12 3.5 21 19.5H3z') + _s('M12 9.5v5') + _r(11, 16, 2, 2),
  'globe':
      _c(12, 12, 8.5) +
          _s(
            'M3.5 12h17M12 3.5c2.4 2.4 3.4 5.3 3.4 8.5s-1 6.1-3.4 8.5c-2.4-2.4-3.4-5.3-3.4-8.5s1-6.1 3.4-8.5z',
          ),
  'bolt': _f('M13 2.5 5 13.5h6l-1 8 8-11h-6z'),
  'clock': _c(12, 12, 8.5) + _s('M12 7.5V12l3 2'),
  'filter': _s('M4 5.5h16l-6.5 7.5v6L10.5 21v-8z'),
  'list': _s('M4 6.5h16M4 12h16M4 17.5h10'),
  'grid': _o(4, 4, 6.5, 6.5) + _o(13.5, 4, 6.5, 6.5) + _o(4, 13.5, 6.5, 6.5) + _r(13.5, 13.5, 6.5, 6.5),
  'more': _r(4, 10.5, 3, 3) + _r(10.5, 10.5, 3, 3) + _r(17, 10.5, 3, 3),
  'eye':
      _s('M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z') + _r(10, 10, 4, 4),
  'sort': _s('M7 4v16M3.5 16.5 7 20l3.5-3.5M13 6.5h7.5M13 12h5.5M13 17.5h3'),
  'profile': _r(8.5, 3.5, 7, 7) + _s('M4.5 20.5v-3a3.5 3.5 0 0 1 3.5-3.5h8a3.5 3.5 0 0 1 3.5 3.5v3'),
  'profiles':
      _o(12.5, 3.5, 6, 6) +
          _s('M14.5 13h2.5a3 3 0 0 1 3 3v3') +
          _r(5, 7, 6, 6) +
          _s('M2.5 20.5v-1.5a3 3 0 0 1 3-3h5a3 3 0 0 1 3 3v1.5'),
  'share': _s('M12 14.5V4.5') + _f('M7.5 9 12 3.5 16.5 9z') + _s('M8 12.5H4.5v8h15v-8H16'),
  'shield':
      _s('M12 3 19.5 6v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6z') +
          _f('M12 3 4.5 6v5.5c0 4.5 3.2 8 7.5 9.5z'),
  'offline':
      _s('M3.5 9.2a12 12 0 0 1 17 0M6.8 12.6a7.3 7.3 0 0 1 10.4 0') +
          _r(10, 15.5, 4, 4) +
          _s('M4 3.5 20 20.5'),
  'image': _o(3.5, 4.5, 17, 15) + _f('M3.5 19.5 9 12.5l4 4.5 2.5-2.5 5 5z') + _r(14.5, 7.5, 3, 3),
  'keyboard': _o(2.5, 6, 19, 12) + _s('M6 10h1M9.5 10h1M13 10h1M16.5 10h1M7.5 14.5h9'),
  'layers': _s('M12 2 2 7l10 5 10-5z') + _s('M2 12l10 5 10-5') + _s('M2 17l10 5 10-5'),
};

/// Every icon name the app can draw.
typedef IconName = String;

/// The names, for the settings icon sheet and for tests.
List<String> get iconNames => glyphBodies.keys.toList(growable: false);

/// Kept so `_rawGlyphs` is referenced; the set is authored inline like the JSX.
Map<String, String> get rawGlyphs => _rawGlyphs;
