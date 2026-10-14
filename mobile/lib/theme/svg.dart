import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A tiny, dependency-free SVG renderer for the subset PlayzAnime's icon set
/// actually uses: `path`, `rect`, `circle` and `text`, with the `d` grammar
/// `M m L l H h V v C c S s Q q T t A a Z z`.
///
/// The desktop app draws its icons as inline `<svg>` in React. Rather than pull
/// in a full SVG runtime (which would add weight and still choke on `<text>`),
/// the glyph bodies are kept verbatim and rasterised into `ui.Path` once, then
/// cached — every icon in the app is a `drawPath` call after the first frame.
class TextRun {
  const TextRun({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.weight,
  });

  final String text;
  final double x;
  final double y;
  final double fontSize;
  final FontWeight weight;
}

/// One drawable piece of a glyph.
class GlyphPart {
  const GlyphPart(this.path, {this.strokeWidth = 0, this.text});

  final ui.Path path;

  /// 0 means "fill with currentColor", otherwise stroke at this width.
  final double strokeWidth;

  final TextRun? text;

  bool get isFill => strokeWidth <= 0 && text == null;
  bool get isStroke => strokeWidth > 0;
}

/// A parsed icon: the parts plus the box it was drawn in.
class Glyph {
  const Glyph(this.parts);

  final List<GlyphPart> parts;
}

// ── Element splitting ───────────────────────────────────────────────────────

final _elementRe = RegExp(
  r'<(path|rect|circle|text)\b([^>]*?)(?:/>|>(.*?)</text>)',
  dotAll: true,
);
final _attrRe = RegExp(r'([a-zA-Z-]+)\s*=\s*"([^"]*)"');

double _attr(Map<String, String> a, String name, [double fallback = 0]) {
  final raw = a[name];
  if (raw == null) return fallback;
  return double.tryParse(raw) ?? fallback;
}

/// Parses an SVG fragment body into a [Glyph].
///
/// [defaultStroke] is the icon's stroke width; elements that set
/// `stroke="none"` and `fill="currentColor"` become fills, everything else is
/// stroked at [defaultStroke] unless it carries an explicit `stroke-width`.
Glyph buildGlyph(String body, double defaultStroke) {
  final parts = <GlyphPart>[];

  for (final m in _elementRe.allMatches(body)) {
    final tag = m.group(1)!;
    final attrs = <String, String>{};
    for (final a in _attrRe.allMatches(m.group(2) ?? '')) {
      attrs[a.group(1)!] = a.group(2)!;
    }

    switch (tag) {
      case 'path':
        final d = attrs['d'];
        if (d == null || d.isEmpty) continue;
        final path = parseSvgPath(d);
        if (attrs['fill'] == 'currentColor' && attrs['stroke'] == 'none') {
          parts.add(GlyphPart(path));
        } else {
          final w = double.tryParse(attrs['stroke-width'] ?? '') ?? defaultStroke;
          parts.add(GlyphPart(path, strokeWidth: w));
        }

      case 'rect':
        final r = Rect.fromLTWH(
          _attr(attrs, 'x'),
          _attr(attrs, 'y'),
          _attr(attrs, 'width'),
          _attr(attrs, 'height'),
        );
        final rx = _attr(attrs, 'rx');
        parts.add(
          rx > 0
              ? GlyphPart(ui.Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rx))))
              : GlyphPart(ui.Path()..addRect(r)),
        );

      case 'circle':
        final path = ui.Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(_attr(attrs, 'cx'), _attr(attrs, 'cy')),
              radius: _attr(attrs, 'r'),
            ),
          );
        parts.add(GlyphPart(path, strokeWidth: defaultStroke));

      case 'text':
        final content = m.group(3) ?? '';
        if (content.isEmpty) continue;
        parts.add(
          GlyphPart(
            ui.Path(),
            text: TextRun(
              text: content,
              x: _attr(attrs, 'x'),
              y: _attr(attrs, 'y'),
              fontSize: _attr(attrs, 'font-size', 10),
              weight: _fontWeight(attrs['font-weight']),
            ),
          ),
        );
    }
  }

  return Glyph(parts);
}

FontWeight _fontWeight(String? raw) {
  final n = int.tryParse(raw ?? '');
  if (n == null) return FontWeight.w400;
  return switch (n) {
    <= 200 => FontWeight.w200,
    <= 300 => FontWeight.w300,
    <= 400 => FontWeight.w400,
    <= 500 => FontWeight.w500,
    <= 600 => FontWeight.w600,
    <= 700 => FontWeight.w700,
    <= 800 => FontWeight.w800,
    _ => FontWeight.w900,
  };
}

// ── `d` grammar ─────────────────────────────────────────────────────────────

/// Parses an SVG path `d` string into a [ui.Path].
///
/// Absolute commands only after the first; implicit repeats are handled the way
/// the spec requires (a second coordinate pair after `M` is an `L`, after `m` an
/// `l`).
ui.Path parseSvgPath(String d) {
  final path = ui.Path();
  final s = _Scan(d);

  double cx = 0, cy = 0; // current point
  double sx = 0, sy = 0; // subpath start
  double lastCx = 0, lastCy = 0; // last cubic control point
  double lastQx = 0, lastQy = 0; // last quadratic control point
  String cmd = '';
  bool started = false;

  while (true) {
    s.skipSeparators();
    if (s.done) break;

    if (s.atCommand) {
      cmd = s.readCommand();
    } else if (cmd.isEmpty) {
      break;
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }

    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? cx : 0.0;
    final oy = rel ? cy : 0.0;

    switch (cmd.toUpperCase()) {
      case 'M':
        cx = ox + s.number();
        cy = oy + s.number();
        sx = cx;
        sy = cy;
        if (!started) {
          path.moveTo(cx, cy);
          started = true;
        } else {
          path.moveTo(cx, cy);
        }

      case 'L':
        cx = ox + s.number();
        cy = oy + s.number();
        path.lineTo(cx, cy);

      case 'H':
        cx = ox + s.number();
        path.lineTo(cx, cy);

      case 'V':
        cy = oy + s.number();
        path.lineTo(cx, cy);

      case 'C':
        final x1 = ox + s.number(), y1 = oy + s.number();
        final x2 = ox + s.number(), y2 = oy + s.number();
        cx = ox + s.number();
        cy = oy + s.number();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        lastCx = x2;
        lastCy = y2;

      case 'S':
        final x2 = ox + s.number(), y2 = oy + s.number();
        final ex = ox + s.number(), ey = oy + s.number();
        final x1 = 2 * cx - lastCx;
        final y1 = 2 * cy - lastCy;
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        lastCx = x2;
        lastCy = y2;
        cx = ex;
        cy = ey;

      case 'Q':
        final x1 = ox + s.number(), y1 = oy + s.number();
        final ex = ox + s.number(), ey = oy + s.number();
        path.quadraticBezierTo(x1, y1, ex, ey);
        lastQx = x1;
        lastQy = y1;
        cx = ex;
        cy = ey;

      case 'T':
        final ex = ox + s.number(), ey = oy + s.number();
        final x1 = 2 * cx - lastQx;
        final y1 = 2 * cy - lastQy;
        path.quadraticBezierTo(x1, y1, ex, ey);
        lastQx = x1;
        lastQy = y1;
        cx = ex;
        cy = ey;

      case 'A':
        final rx = s.number().abs();
        final ry = s.number().abs();
        final rot = s.number();
        final largeArc = s.flag();
        final sweep = s.flag();
        final ex = ox + s.number();
        final ey = oy + s.number();
        if (rx == 0 || ry == 0) {
          path.lineTo(ex, ey);
        } else {
          path.arcToPoint(
            Offset(ex, ey),
            radius: Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: largeArc,
            clockwise: sweep,
          );
        }
        cx = ex;
        cy = ey;

      case 'Z':
        path.close();
        cx = sx;
        cy = sy;

      default:
        // Unknown command: stop rather than loop forever.
        return path;
    }
  }

  return path;
}

class _Scan {
  _Scan(this.src);

  final String src;
  int i = 0;

  bool get done => i >= src.length;

  bool get atCommand {
    if (done) return false;
    final c = src.codeUnitAt(i);
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }

  void skipSeparators() {
    while (!done) {
      final c = src.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        i++;
      } else {
        break;
      }
    }
  }

  String readCommand() => src[i++];

  double number() {
    skipSeparators();
    final start = i;
    if (!done && (src[i] == '-' || src[i] == '+')) i++;
    var seenDot = false;
    while (!done) {
      final c = src.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        i++;
      } else if (c == 0x2E) {
        // A second '.' without a separating space starts the next number.
        if (seenDot) break;
        seenDot = true;
        i++;
      } else if (c == 0x65 || c == 0x45) {
        i++;
        if (!done && (src[i] == '-' || src[i] == '+')) i++;
      } else {
        break;
      }
    }
    if (i == start) {
      i++;
      return 0;
    }
    return double.tryParse(src.substring(start, i)) ?? 0;
  }

  /// Arc flags are single characters and may be run together ("0 0110 20").
  bool flag() {
    skipSeparators();
    if (done) return false;
    final c = src.codeUnitAt(i);
    if (c == 0x30) {
      i++;
      return false;
    }
    if (c == 0x31) {
      i++;
      return true;
    }
    return number() != 0;
  }
}
