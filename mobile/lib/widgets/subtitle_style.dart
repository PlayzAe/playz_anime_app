import 'package:flutter/material.dart' hide Ink;

import '../models/local.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Subtitle look, from Settings. Port of the desktop `SubtitleCustomizer.tsx`
/// options (size, colour, background, outline, position), shared by the
/// player sheet, Settings → Watching and downloads.
class SubStyle {
  const SubStyle({required this.size, required this.color, required this.background, required this.outline, required this.bold, required this.lift});

  factory SubStyle.of(Settings s) => SubStyle(
        size: s.subSize,
        color: hexColor(s.subColor) ?? Colors.white,
        background: s.subBackground,
        outline: s.subOutline,
        bold: s.subBold,
        lift: s.subLift,
      );

  final double size;
  final Color color;
  final double background;
  final bool outline;
  final bool bold;

  /// Extra distance from the bottom, 0–1 of a fifth of the video height.
  final double lift;

  TextStyle text({required bool full}) => body((full ? 21 : 15) * size, weight: bold ? FontWeight.w700 : FontWeight.w500, height: 1.25).copyWith(
        color: color,
        shadows: outline
            ? const [
                Shadow(blurRadius: 3, color: Colors.black),
                Shadow(offset: Offset(1.2, 1.2), blurRadius: 1.5, color: Colors.black),
                Shadow(offset: Offset(-1.2, -1.2), blurRadius: 1.5, color: Colors.black),
                Shadow(offset: Offset(1.2, -1.2), blurRadius: 1.5, color: Colors.black),
                Shadow(offset: Offset(-1.2, 1.2), blurRadius: 1.5, color: Colors.black),
              ]
            : null,
      );

  Widget render(String cue, {required bool full}) {
    final t = Text(cue, textAlign: TextAlign.center, style: text(full: full));
    if (background <= 0) return t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withAlpha((background * 255).round()), borderRadius: BorderRadius.circular(4)),
      child: t,
    );
  }
}

const kSubColors = ['FFFFFF', 'FFE14D', '9BE7FF', 'B8F28A', 'FFB3C7'];

/// Live editor with a preview. Changes save as they happen.
class SubtitleStyleEditor extends StatefulWidget {
  const SubtitleStyleEditor({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<SubtitleStyleEditor> createState() => _SubtitleStyleEditorState();
}

class _SubtitleStyleEditorState extends State<SubtitleStyleEditor> {
  void _patch(Settings Function(Settings) f) {
    Store.i.patchSettings(f);
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.i.settings;
    final st = SubStyle.of(s);
    final a = accentOf(context);
    Widget label(String t, [String? v]) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Row(children: [
            Text(t, style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
            const Spacer(),
            if (v != null) Text(v, style: body(13, weight: FontWeight.w700)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [Color(0xFF3A4A5C), Color(0xFF6B5B4B)]),
        ),
        alignment: Alignment.bottomCenter,
        padding: EdgeInsets.only(bottom: 10 + st.lift * 30, left: 12, right: 12),
        child: st.render('Subtitles will look like this.', full: false),
      ),
      label('Size', '${(s.subSize * 100).round()}%'),
      Slider(value: s.subSize.clamp(0.6, 1.8), min: 0.6, max: 1.8, divisions: 12, activeColor: a, onChanged: (v) => _patch((x) => x.copyWith(subSize: v))),
      label('Colour'),
      const SizedBox(height: 6),
      Row(children: [
        for (final c in kSubColors)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Pressable(
              onTap: () => _patch((x) => x.copyWith(subColor: c)),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hexColor(c) ?? Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: s.subColor == c ? a : Lines.line2, width: s.subColor == c ? 3 : 1),
                ),
              ),
            ),
          ),
      ]),
      label('Background', s.subBackground == 0 ? 'None' : '${(s.subBackground * 100).round()}%'),
      Slider(value: s.subBackground.clamp(0, 0.9), max: 0.9, divisions: 9, activeColor: a, onChanged: (v) => _patch((x) => x.copyWith(subBackground: v))),
      label('Position', s.subLift == 0 ? 'Bottom' : 'Raised'),
      Slider(value: s.subLift.clamp(0, 1), divisions: 5, activeColor: a, onChanged: (v) => _patch((x) => x.copyWith(subLift: v))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text('Outline', style: body(14))),
        PzToggle(value: s.subOutline, onChanged: (v) => _patch((x) => x.copyWith(subOutline: v))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text('Bold', style: body(14))),
        PzToggle(value: s.subBold, onChanged: (v) => _patch((x) => x.copyWith(subBold: v))),
      ]),
    ]);
  }
}
