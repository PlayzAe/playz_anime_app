import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/icons.dart';
import '../theme/svg.dart';

/// Draws one of PlayzAnime's own glyphs.
///
/// Compiled `ui.Path`s are cached per (name, stroke) so a list of 200 posters
/// costs one `drawPath` batch each frame and nothing on layout. The whole thing
/// is a single `CustomPaint` — cheaper than a widget tree per icon and it keeps
/// the square caps and mitred joins the set is built on.
class PzIcon extends StatelessWidget {
  const PzIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.stroke = 1.7,
    this.color,
  });

  final IconName name;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(
          glyph: _cache.putIfAbsent(
            '$name@$stroke',
            () => buildGlyph(glyphBodies[name] ?? '', stroke),
          ),
          color: color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFFEFE9E1),
          stroke: stroke,
          devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        ),
      ),
    );
  }
}

final Map<String, Glyph> _cache = <String, Glyph>{};

class _IconPainter extends CustomPainter {
  _IconPainter({
    required this.glyph,
    required this.color,
    required this.stroke,
    required this.devicePixelRatio,
  });

  final Glyph glyph;
  final Color color;
  final double stroke;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    // The glyphs are authored on a 24px grid.
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Only a couple of glyphs override the stroke width (the search handle);
    // one spare paint covers them without allocating inside the loop.
    final altStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    for (final part in glyph.parts) {
      final run = part.text;
      if (run != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: run.text,
            style: TextStyle(
              color: color,
              fontSize: run.fontSize,
              fontWeight: run.weight,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(run.x - tp.width / 2, run.y - run.fontSize));
        continue;
      }

      if (part.isFill) {
        canvas.drawPath(part.path, fillPaint);
      } else if (part.strokeWidth == stroke) {
        canvas.drawPath(part.path, strokePaint);
      } else {
        altStroke.strokeWidth = part.strokeWidth;
        canvas.drawPath(part.path, altStroke);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      !identical(old.glyph, glyph) ||
      old.devicePixelRatio != devicePixelRatio;
}

/// The PlayzAnime mark: a vermilion seal (hanko) with a carved P.
///
/// The P's counter is a play shape resting against the stem. The frame has two
/// chips, the way a hand-carved seal wears, so the mark never reads as a stock
/// rounded square.
class PzLogo extends StatelessWidget {
  const PzLogo({super.key, this.size = 32, this.accent, this.framed, this.radius});

  final double size;

  /// Defaults to the live accent seal colour.
  final Color? accent;

  /// The inner frame lines are too fine below ~28px.
  final bool? framed;

  /// Corner radius. Defaults to the 9/64 ratio the seal uses.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final showFrame = framed ?? size >= 28;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SealPainter(
          accentColor: accent ?? PzAccent.of(context).base,
          framed: showFrame,
          radius: radius ?? size * 9 / 64,
        ),
      ),
    );
  }
}

const String _pPath = 'M17 14H35A12.5 12.5 0 0 1 35 39H27V48L17 51Z';
const String _counterPath = 'M27 20.5V32.5L38.5 26.5Z';
const List<String> _framePaths = <String>[
  'M40 8.5H51A4.5 4.5 0 0 1 55.5 13V44',
  'M55.5 49V51A4.5 4.5 0 0 1 51 55.5H22',
  'M16 55.5H13A4.5 4.5 0 0 1 8.5 51V13A4.5 4.5 0 0 1 13 8.5H35',
];

class _SealPainter extends CustomPainter {
  _SealPainter({required this.accentColor, required this.framed, required this.radius});

  final Color accentColor;
  final bool framed;
  final double radius;

  static ui.Path? _p;
  static ui.Path? _counter;
  static List<ui.Path>? _frames;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s);

    const carve = Color(0xFFF6EFE4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2, 2, 60, 60), Radius.circular(9)),
      Paint()..color = accentColor,
    );

    if (framed) {
      final frames = _frames ??= _framePaths.map(parseSvgPath).toList(growable: false);
      final paint = Paint()
        ..color = carve
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.butt;
      for (final f in frames) {
        canvas.drawPath(f, paint);
      }
    }

    // The P with its counter cut out: even-odd fill, exactly like the SVG.
    final p = _p ??= parseSvgPath(_pPath);
    final counter = _counter ??= parseSvgPath(_counterPath);
    final combined = ui.Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(p, Offset.zero)
      ..addPath(counter, Offset.zero);
    canvas.drawPath(combined, Paint()..color = carve);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.accentColor != accentColor || old.framed != framed || old.radius != radius;
}
