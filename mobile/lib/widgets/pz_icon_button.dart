import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import 'pz_icon.dart';

/// `.icon-btn` — the 36x36 glyph button.
///
/// Used everywhere a phone screen has one small action: back, close, sort,
/// overflow, a per-row trash. It carries no fill until you touch it, which is
/// what keeps a toolbar of five of them from reading as five buttons.
///
/// The label was the desktop's `title` tooltip and is the screen-reader name
/// here — a hover bubble is a mouse affordance and this build is mostly thumbs.
class PzIconButton extends StatelessWidget {
  const PzIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 20,
    this.active = false,
    this.danger = false,
    this.box = 36,
    this.color,
  });

  final IconName icon;

  /// Null disables it: `.35` opacity, no fill, no press.
  final VoidCallback? onPressed;

  /// Accessibility name. Not drawn anywhere, deliberately.
  final String? tooltip;

  /// The glyph's size, not the box's.
  final double size;

  /// `.is-active` — the pressed-in look for a toggled button (view mode, mute),
  /// also reused for the current pane in a header.
  final bool active;

  /// Destructive affordance: tints the glyph `--bad`, so a trash can does not
  /// have to know a hex value.
  final bool danger;

  /// The drawn box. The desktop's title-bar override was 32x30; anything under
  /// 44 still gets a 44dp hit band around it.
  final double box;

  /// Pin the glyph's tone — an offline notice, a status companion. Hover then
  /// lights the fill but leaves the colour alone.
  final Color? color;

  @override
  Widget build(BuildContext context) => _Body(host: this);
}

class _Body extends StatefulWidget {
  const _Body({required this.host});

  final PzIconButton host;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  PzIconButton get _btn => widget.host;

  bool get _live => _btn.onPressed != null;

  @override
  Widget build(BuildContext context) {
    // `:hover:not(:disabled)` and `.is-active` paint the same fill.
    final lit = _live && (_hover || _btn.active);
    final pinned = _btn.color;
    final rest = pinned ?? (_btn.danger ? Tone.bad : Paper.paper2);
    final litInk = _btn.danger ? Tone.bad : (pinned ?? Paper.paper);

    // `.icon-btn:disabled { opacity: .35 }` — dimmer than a disabled button
    // (.45), because an unfilled glyph has nothing else to carry the state.
    final ink = _live ? (lit ? litInk : rest) : withOpacityLinear(rest, 0.35);

    Widget drawn = SizedBox(
      width: _btn.box,
      height: _btn.box,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: lit ? Ink.ink3 : _clear,
          borderRadius: BorderRadius.circular(Radii.r2),
        ),
        child: Center(child: PzIcon(_btn.icon, size: _btn.size, color: ink)),
      ),
    );

    if (_focus) drawn = _FocusRing(radius: Radii.r2, child: drawn);

    // The desktop's `transform: translateY(1px)` on press, as a fraction of the
    // box it translates.
    final press = AnimatedSlide(
      offset: _down ? Offset(0, 1 / math.max(_btn.box, 1)) : Offset.zero,
      duration: _motion(context, Motion.fast),
      curve: Motion.ease,
      child: drawn,
    );

    // 36dp is a mouse target. The band is what a thumb lands on; the glyph stays
    // centred in it, so a row of these still lines up on the 36dp grid it was
    // drawn for while every tap gets its 44.
    final band = math.max(_btn.box, 44.0);

    return SizedBox(
      width: band,
      height: band,
      child: Center(
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
                if (_live) _btn.onPressed!.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _live ? (_) => setState(() => _down = true) : null,
            onTapUp: _live ? (_) => setState(() => _down = false) : null,
            onTapCancel: () => setState(() => _down = false),
            onTap: _live ? _btn.onPressed : null,
            // The glyph has no text of its own, so this label is the whole name.
            child: Semantics(
              container: true,
              button: true,
              enabled: _live,
              label: _btn.tooltip,
              child: press,
            ),
          ),
        ),
      ),
    );
  }
}

/// `:focus-visible { outline: 2px solid var(--paper); outline-offset: 2px }`,
/// painted outside the box so a focus move never reflows a toolbar.
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

const Color _clear = Color(0x00000000);

/// `@media (prefers-reduced-motion: reduce)` collapses every duration.
Duration _motion(BuildContext context, Duration duration) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : duration;
