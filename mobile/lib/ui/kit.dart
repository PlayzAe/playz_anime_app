import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';

import '../models/media.dart';
import '../services/format.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';

/// Mobile UI kit. Same ink/paper/seal language as the desktop CSS
/// (`tokens.css`), sized for thumbs: 44px+ targets, 16px gutter.

const double kGutter = 16;
const Curve kEase = Cubic(0.2, 0.8, 0.2, 1); // --ease
const Duration kFast = Duration(milliseconds: 140);
const Duration kMed = Duration(milliseconds: 240);

/// Condensed display type, like the desktop hero (`font-stretch: 72%`).
TextStyle display(double size, {Color color = Paper.paper, double height = 0.95}) => TextStyle(
      fontFamily: 'Archivo',
      fontSize: size,
      height: height,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.02 * size,
      color: color,
      fontVariations: const [FontVariation('wdth', 72), FontVariation('wght', 800)],
    );

TextStyle body(double size, {Color color = Paper.paper, FontWeight weight = FontWeight.w500, double? height}) =>
    TextStyle(fontFamily: 'Archivo', fontSize: size, color: color, fontWeight: weight, height: height);

Color accentOf(BuildContext c) => PzAccent.of(c).base;

/// AniList's `#e4a15d` cover colours → [Color]; null when missing.
Color? hexColor(String? hex) {
  if (hex == null || hex.length < 7) return null;
  final v = int.tryParse(hex.substring(1, 7), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

// ── Motion ──────────────────────────────────────────────────────────────────

/// Tap target with a small press-in bounce and a light haptic.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? const Duration(milliseconds: 90) : const Duration(milliseconds: 320),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Fades and lifts its child in once, after [delay]. Used to stagger shelves.
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 14});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: kEase);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
        ),
      );
}

/// Fade + slight rise page transition for every pushed route.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final t = CurvedAnimation(parent: a, curve: kEase);
        return FadeTransition(
          opacity: t,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(t), child: child),
        );
      },
    );

Future<T?> go<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(fadeRoute(page));

// ── Primitives ──────────────────────────────────────────────────────────────

/// Primary (seal) and ghost buttons, as in `Controls.tsx`.
class PzBtn extends StatelessWidget {
  const PzBtn(this.label, {super.key, this.onTap, this.icon, this.primary = false, this.compact = false, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool primary;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context);
    final fg = primary ? Seal.accentInk : Paper.paper;
    return Pressable(
      onTap: busy ? null : onTap,
      child: AnimatedOpacity(
        duration: kFast,
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: compact ? 38 : 46,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          decoration: BoxDecoration(
            color: primary ? accent : Ink.ink2,
            borderRadius: BorderRadius.circular(7),
            border: primary ? null : Border.all(color: Lines.line2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else if (icon != null)
              PzIcon(icon!, size: compact ? 16 : 18, color: fg),
            if (busy || icon != null) const SizedBox(width: 8),
            Text(label, style: body(compact ? 13.5 : 15, color: fg, weight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class RoundIcon extends StatelessWidget {
  const RoundIcon(this.icon, {super.key, this.onTap, this.size = 40, this.iconSize = 20, this.filled = true, this.color});

  final String icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.88,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Ink.ink2.withAlpha(0xE6) : null,
            shape: BoxShape.circle,
            border: filled ? Border.all(color: Lines.line) : null,
          ),
          child: PzIcon(icon, size: iconSize, color: color ?? Paper.paper),
        ),
      );
}

/// Segmented control used across Settings and filters.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Ink.ink1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Lines.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            Pressable(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: kMed,
                curve: kEase,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: v == value ? Ink.ink3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: body(13.5,
                        color: v == value ? Paper.paper : Paper.paper3,
                        weight: v == value ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
        ]),
      );
}

/// The desktop's square toggle: a paper knob that slides, ink when off.
class PzToggle extends StatelessWidget {
  const PzToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: kMed,
          curve: kEase,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? Paper.paper : Ink.ink3,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: value ? Paper.paper : Lines.line2),
          ),
          child: AnimatedAlign(
            duration: kMed,
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? Ink.ink0 : Paper.paper4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, this.on = false, this.onTap});

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: kMed,
        curve: kEase,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: on ? accent : Ink.ink2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? accent : Lines.line),
        ),
        child: Text(label,
            style: body(13, color: on ? Seal.accentInk : Paper.paper2, weight: on ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.height = 3});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(children: [
            Container(color: Paper.paper.withAlpha(0x2E)),
            FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: Container(color: accentOf(context))),
          ]),
        ),
      );
}

/// Pulsing placeholder block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = 7});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(Ink.ink2, Ink.ink3, _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.onAction});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 26, kGutter, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(19, weight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: body(12.5, color: Paper.paper3)),
              ],
            ]),
          ),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Row(children: [
                  Text(action!, style: body(13, color: Paper.paper2, weight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const PzIcon('arrowRight', size: 14, color: Paper.paper2),
                ]),
              ),
            ),
        ]),
      );
}

/// Horizontal shelf of fixed-width items.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.height, required this.itemCount, required this.itemBuilder, this.itemWidth = 118, this.gap = 12});

  final double height;
  final double itemWidth;
  final double gap;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          itemCount: itemCount,
          separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: (c, i) => SizedBox(width: itemWidth, child: itemBuilder(c, i)),
        ),
      );
}

/// Poster card: 2:3 cover, title, one meta line. Bounces on press.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.media, required this.title, required this.onTap, this.badge, this.meta});

  final Media media;
  final String title;
  final VoidCallback onTap;
  final String? badge;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final score = Fmt.scoreLabel(media.averageScore);
    return Pressable(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            PzImage(url: Fmt.coverOf(media), radius: BorderRadius.circular(7), blurHashColor: hexColor(media.coverImage?.color)),
            if (score != null)
              Positioned(
                top: 6,
                right: 6,
                child: _Tag(score, icon: 'bolt'),
              ),
            if (badge != null) Positioned(left: 6, bottom: 6, child: _Tag(badge!)),
          ]),
        ),
        const SizedBox(height: 7),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 2),
        Text(meta ?? Fmt.posterMeta(media),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11.5, color: Paper.paper3)),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.icon});

  final String text;
  final String? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: Ink.ink0.withAlpha(0xD9), borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[PzIcon(icon!, size: 11, color: Paper.paper), const SizedBox(width: 3)],
          Text(text, style: body(11, weight: FontWeight.w700)),
        ]),
      );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon});

  final String text;
  final String? icon;

  @override
  Widget build(BuildContext context) => _Tag(text, icon: icon);
}

class PosterSkeletons extends StatelessWidget {
  const PosterSkeletons({super.key, this.height = 246});

  final double height;

  @override
  Widget build(BuildContext context) => Shelf(
        height: height,
        itemCount: 5,
        itemBuilder: (_, __) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 2 / 3, child: Skeleton()),
          SizedBox(height: 8),
          Skeleton(height: 12, width: 90),
        ]),
      );
}

/// Empty / error panel, as in `States.tsx`.
class StatePanel extends StatelessWidget {
  const StatePanel({super.key, required this.title, this.message, this.icon = 'info', this.action, this.onAction});

  final String title;
  final String? message;
  final String icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => FadeIn(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(12)),
              child: PzIcon(icon, size: 24, color: Paper.paper2),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: body(16, weight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: body(13, color: Paper.paper3, height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              PzBtn(action!, onTap: onAction, compact: true, icon: 'refresh'),
            ],
          ]),
        ),
      );
}

/// Bottom sheet in the app's ink, with a grab handle.
Future<T?> pzSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: Ink.ink1,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Paper.paper4, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(title, style: body(17, weight: FontWeight.w800)),
          ),
          Flexible(child: builder(c)),
          SizedBox(height: MediaQuery.of(c).padding.bottom + 8),
        ]),
      ),
    );

/// A tappable sheet row with a check when selected.
class SheetOption extends StatelessWidget {
  const SheetOption(this.label, {super.key, required this.selected, required this.onTap, this.sub});

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: selected ? Ink.ink2 : Colors.transparent,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: body(15, weight: selected ? FontWeight.w700 : FontWeight.w500)),
                if (sub != null) Text(sub!, style: body(12, color: Paper.paper3)),
              ]),
            ),
            if (selected) PzIcon('check', size: 18, color: accentOf(context)),
          ]),
        ),
      );
}

/// Snack-style toast in the app's look.
void toast(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Ink.ink3,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    duration: const Duration(seconds: 2),
    content: Text(text, style: body(13.5)),
  ));
}

/// Yes/no dialog. Resolves false when dismissed.
Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'OK'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Ink.ink2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: body(17, weight: FontWeight.w800)),
      content: Text(message, style: body(14, color: Paper.paper2)),
      actions: [
        PzBtn('Cancel', compact: true, onTap: () => Navigator.pop(c, false)),
        PzBtn(action, compact: true, primary: true, onTap: () => Navigator.pop(c, true)),
      ],
    ),
  );
  return ok ?? false;
}
