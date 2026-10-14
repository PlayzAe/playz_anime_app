import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

/// The design system's progress bar: a 3px track with an accent fill.
///
/// [value] is a fraction, not a percentage — views pass 0..1 and it is clamped
/// here, the way the desktop's `ProgressBar` did. When the length of the work
/// is not known yet (a source still resolving, a job waiting on its turn) set
/// [indeterminate] and the bar sweeps a band instead of filling.
class PzProgress extends StatelessWidget {
  const PzProgress({
    super.key,
    required this.value,
    this.height = 3,
    this.color,
    this.track,
    this.indeterminate = false,
  });

  final double value;
  final double height;

  /// Fill colour. Defaults to the live accent — progress is one of the few
  /// places the design spends it.
  final Color? color;

  /// Track colour. Defaults to `rgb(239 233 225 / 0.14)`; the hero's pager and
  /// the poster overlay pass their own.
  final Color? track;

  final bool indeterminate;

  /// `.job-progress.is-waiting .progress-fill { width: 30% }`
  static const double _band = 0.30;

  /// `animation: indeterminate 1.2s ease-in-out infinite`
  static const Duration _sweep = Duration(milliseconds: 1200);

  @override
  Widget build(BuildContext context) {
    final fill = color ?? PzAccent.of(context).base;
    final rest = track ?? Lines.paper14;

    // `prefers-reduced-motion` reduces every transition to 1ms, so a width
    // change is decoration and goes instantly. The sweep is not decoration —
    // a frozen indeterminate bar reads as a hung app — so it keeps turning.
    final instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return SizedBox(
      height: height,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: rest),
            if (indeterminate)
              _Sweep(color: fill)
            else
              AnimatedFractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                duration: instant ? Duration.zero : Motion.med,
                curve: Curves.linear,
                child: ColoredBox(color: fill),
              ),
          ],
        ),
      ),
    );
  }
}

/// The waiting band: 30% of the track, entering from the left edge and leaving
/// past the right one, once every 1.2s.
///
/// Stateful because it has to keep moving; [PzProgress] stays stateless so a
/// view can rebuild the bar on every download tick without restarting the
/// sweep.
class _Sweep extends StatefulWidget {
  const _Sweep({required this.color});

  final Color color;

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: PzProgress._sweep)..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final band = box.maxWidth * PzProgress._band;
        return AnimatedBuilder(
          animation: _run,
          builder: (context, _) {
            // `translateX(-100%)` → `translateX(340%)`, in band widths: fully
            // off the left edge to fully off the right one. The easing is on
            // the timing, so it is applied to the progress, not the value.
            final at = Curves.easeInOut.transform(_run.value) * 4.4 - 1;
            return Stack(
              children: [
                Positioned(
                  left: band * at,
                  top: 0,
                  bottom: 0,
                  width: band,
                  child: ColoredBox(color: widget.color),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
