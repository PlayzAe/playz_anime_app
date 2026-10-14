import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import 'pz_icon.dart';

enum PzButtonSize { sm, md, lg }

enum PzButtonKind { primary, solid, ghost, quiet }

/// `.btn` — the one button the app draws.
///
/// Every number is the desktop's: 30/38/46 tall, gap 8 (6 at `sm`), radius 7,
/// and the `lg` padding is asymmetric on purpose (right 22, left 18) — the wide
/// right edge is what stops a "Play episode" CTA looking cramped beside its
/// trailing glyph. Default kind is `solid`, not `primary`: the accent is spent
/// only on the one action that progresses the user, and that is the caller's
/// decision.
///
/// Hover, press and focus live in here rather than in each view so that all of
/// it lands in one place, and so a touch build still gets the 44dp minimum hit
/// band without every call site remembering to ask for it.
class PzButton extends StatelessWidget {
  const PzButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = PzButtonKind.solid,
    this.size = PzButtonSize.md,
    this.trailing,
    this.expand = false,
    this.loading = false,
  });

  /// Null draws an icon-only button; [icon] or [trailing] has to carry it.
  final String? label;

  /// Null disables the button: dimmed to `.45`, no hover, no press.
  final VoidCallback? onPressed;

  final IconName? icon;
  final PzButtonKind kind;
  final PzButtonSize size;

  /// Drawn after the label. The original's `iconRight` arrived 2px smaller than
  /// the leading icon — a `Widget` here so a count or a chevron fits too.
  final Widget? trailing;

  /// Fill the parent's width. The label then flexes and ellipsises instead of
  /// overflowing.
  final bool expand;

  /// Swaps the leading icon for the app's spinnner ring and blocks presses.
  final bool loading;

  @override
  Widget build(BuildContext context) => _Body(host: this);
}

class _Body extends StatefulWidget {
  const _Body({required this.host});

  final PzButton host;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  PzButton get _btn => widget.host;

  bool get _live => _btn.onPressed != null && !_btn.loading;

  void _activate() {
    if (!_live) return;
    _btn.onPressed!.call();
  }

  /// The live accent, or the default seal colour when something renders a
  /// primary button with no [PzAccent] above it (goldens do). Only the primary
  /// kind asks, so the other three do not rebuild when the accent changes.
  AccentKey _accent(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PzAccent>()?.key0 ?? AccentKey.shu;

  @override
  Widget build(BuildContext context) {
    final size = _btn.size;
    final height = size.box;
    final hovered = _hover && _live;

    final accent = _btn.kind == PzButtonKind.primary ? _accent(context) : AccentKey.shu;

    final (Color bg, Color fg, Color? edge) = switch (_btn.kind) {
      PzButtonKind.primary => (
        hovered ? accent.hi : accent.base,
        Seal.accentInk,
        null,
      ),
      PzButtonKind.solid => (hovered ? Ink.ink4 : Ink.ink3, Paper.paper, null),
      PzButtonKind.ghost => (
        hovered ? Lines.paper08 : _ghostVeil,
        Paper.paper,
        hovered ? Lines.paper28 : Lines.line2,
      ),
      PzButtonKind.quiet => (
        hovered ? Ink.ink2 : _clear,
        hovered ? Paper.paper : Paper.paper2,
        null,
      ),
    };

    // `.btn:disabled { opacity: .45 }`, with the alpha folded into the colours
    // instead of an `Opacity` widget — a disabled button can sit in a scrolling
    // row, and a saveLayer per row is not worth one property.
    final bgFill = _live ? bg : withOpacityLinear(bg, 0.45);
    final ink = _live ? fg : withOpacityLinear(fg, 0.45);
    final edgeFill = edge == null ? null : (_live ? edge : withOpacityLinear(edge, 0.45));

    final label = _btn.label;
    final children = <Widget>[
      if (_btn.loading)
        _Ring(size: size.iconBox, color: ink, animate: !_still(context))
      else if (_btn.icon != null)
        PzIcon(_btn.icon!, size: size.iconBox, color: ink),
      if (label != null)
        _btn.expand
            ? Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: size.type.copyWith(color: ink),
                ),
              )
            : Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: size.type.copyWith(color: ink),
              ),
      if (_btn.trailing != null) _btn.trailing!,
    ];

    Widget drawn = SizedBox(
      height: height,
      width: _btn.expand ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bgFill,
          borderRadius: BorderRadius.circular(Radii.r2),
          border: edgeFill == null ? null : Border.all(color: edgeFill, width: 1),
        ),
        child: Padding(
          padding: size.pad,
          child: Row(
            mainAxisSize: _btn.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: size.gap,
            children: children,
          ),
        ),
      ),
    );

    // The CSS hit box is the drawn one. On a phone the drawn one is too short to
    // hit with a thumb, so the band grows to 44 and the button stays centred
    // inside it — transparent, so nothing about the row's look changes.
    if (!_btn.expand) {
      drawn = ConstrainedBox(constraints: const BoxConstraints(minWidth: 44), child: drawn);
    }

    // `:active { transform: translateY(1px) }` — 1px as a fraction of the
    // button's own height, which is what AnimatedSlide measures in.
    final press = AnimatedSlide(
      offset: _down ? Offset(0, 1 / height) : Offset.zero,
      duration: _motion(context, Motion.fast),
      curve: Motion.ease,
      child: drawn,
    );

    return SizedBox(
      height: math.max(height, 44),
      width: _btn.expand ? double.infinity : null,
      child: Center(
        widthFactor: _btn.expand ? null : 1,
        child: FocusableActionDetector(
          enabled: _live,
          mouseCursor: _live ? SystemMouseCursors.click : MouseCursor.defer,
          onShowHoverHighlight: (v) {
            if (v != _hover) setState(() => _hover = v);
          },
          onShowFocusHighlight: (v) {
            if (v != _focus) setState(() => _focus = v);
          },
          // Enter and Space already map to ActivateIntent in the default
          // shortcut table; the detector only has to answer it.
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _live ? (_) => setState(() => _down = true) : null,
            onTapUp: _live ? (_) => setState(() => _down = false) : null,
            onTapCancel: () => setState(() => _down = false),
            onTap: _live ? _activate : null,
            child: _focus ? _FocusRing(radius: Radii.r2, child: press) : press,
          ),
        ),
      ),
    );
  }
}

/// `.spinner` scaled down to sit inside a button: a 2px full ring at 16% with a
/// quarter arc on top, 800ms linear.
///
/// The ring is drawn in the button's own ink rather than the app's `--paper`,
/// because on a primary button the ink is `--accent-ink` and a paper ring on
/// vermilion would read as a second, brighter element.
class _Ring extends StatefulWidget {
  const _Ring({required this.size, required this.color, required this.animate});

  final double size;
  final Color color;
  final bool animate;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _spin.repeat();
  }

  @override
  void didUpdateWidget(_Ring old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.animate && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: RotationTransition(
      // Reduced motion keeps the ring, parked at the top of its travel.
      turns: widget.animate ? _spin : const AlwaysStoppedAnimation<double>(0),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RingPainter(color: widget.color),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color});

  final Color color;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - _width) / 2;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = withOpacityLinear(color, 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi / 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// `:focus-visible { outline: 2px solid var(--paper); outline-offset: 2px }`.
///
/// Painted 2px outside the box rather than laid out there, so tabbing through a
/// toolbar never reflows it. Web and keyboard only; a phone never builds it.
class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      child,
      Positioned(
        left: -2,
        top: -2,
        right: -2,
        bottom: -2,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Paper.paper, width: 2),
              borderRadius: BorderRadius.circular(radius + 2),
            ),
          ),
        ),
      ),
    ],
  );
}

/// The per-size geometry, straight off `.btn-sm/-md/-lg`.
extension _SizeGeometry on PzButtonSize {
  double get box => switch (this) {
    PzButtonSize.sm => 30,
    PzButtonSize.md => 38,
    PzButtonSize.lg => 46,
  };

  /// `size === 'lg' ? 18 : size === 'sm' ? 15 : 17` from the original JSX.
  double get iconBox => switch (this) {
    PzButtonSize.sm => 15,
    PzButtonSize.md => 17,
    PzButtonSize.lg => 18,
  };

  double get gap => this == PzButtonSize.sm ? 6 : 8;

  EdgeInsets get pad => switch (this) {
    PzButtonSize.sm => const EdgeInsets.symmetric(horizontal: 11),
    PzButtonSize.md => const EdgeInsets.symmetric(horizontal: 15),
    PzButtonSize.lg => const EdgeInsets.only(left: 18, right: 22),
  };

  TextStyle get type => switch (this) {
    PzButtonSize.sm => Type.buttonSm,
    PzButtonSize.md => Type.button,
    PzButtonSize.lg => Type.buttonLg,
  };
}

/// `rgb(12 11 10 / 0.25)` — `.btn-ghost`'s veil. Only that one rule uses it, so
/// it never earned a token.
const Color _ghostVeil = Color(0x400C0B0A);

const Color _clear = Color(0x00000000);

/// `@media (prefers-reduced-motion: reduce)` collapses every duration; Flutter
/// surfaces the same preference through `MediaQuery.disableAnimations`.
Duration _motion(BuildContext context, Duration duration) =>
    _still(context) ? Duration.zero : duration;

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
