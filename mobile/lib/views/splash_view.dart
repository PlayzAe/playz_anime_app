import 'package:flutter/material.dart' hide Ink;

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../widgets/pz_icon.dart';

/// The opening intro every time PlayzAnime launches.
/// Ported 1:1 from `src/renderer/components/Splash.tsx`.
/// Animated ink seal stamp, title letters reveal, and aurora wash. Tap to skip!
class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _stampScale;
  late final Animation<double> _stampRotate;
  late final Animation<double> _stampOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<double> _tagOpacity;

  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Stamp springs down between 100ms and 600ms
    _stampScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 2.6, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 50),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.05, 0.45)));

    _stampRotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -0.25, end: 0.0).chain(CurveTween(curve: Curves.easeOutQuad)), weight: 40),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.05, 0.45)));

    _stampOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.05, 0.25)),
    );

    // PlayzAnime letters fade in from 35% to 70%
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.35, 0.70, curve: Curves.easeOut)),
    );

    // Subtitle アニメ ・ マンガ fades in from 65% to 90%
    _tagOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.65, 0.90, curve: Curves.easeOut)),
    );

    _ctrl.forward().then((_) => _finish());
  }

  void _finish() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = PzAccent.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: Ink.ink0,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Aurora ambient glow
            Positioned(
              top: -60,
              left: -60,
              right: -60,
              height: 320,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 0.8,
                    colors: [
                      accent.base.withAlpha(45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Center intro animation
            Center(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Carved P Stamp
                      Opacity(
                        opacity: _stampOpacity.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _stampScale.value,
                          child: Transform.rotate(
                            angle: _stampRotate.value,
                            child: const PzLogo(size: 88),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Wordmark
                      Opacity(
                        opacity: _textOpacity.value.clamp(0.0, 1.0),
                        child: Text(
                          'PlayzAnime',
                          style: Type.display.copyWith(
                            fontSize: 32,
                            letterSpacing: -0.5,
                            color: Paper.paper,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Japanese tag
                      Opacity(
                        opacity: _tagOpacity.value.clamp(0.0, 1.0),
                        child: Text(
                          'アニメ ・ マンガ',
                          style: TextStyle(
                            fontFamily: 'Noto Sans JP',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 4.0,
                            color: Paper.paper3,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Skip hint at bottom
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Tap to skip',
                  style: Type.caption.copyWith(color: Paper.paper4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
