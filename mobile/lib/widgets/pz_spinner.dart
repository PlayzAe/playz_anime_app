import 'package:flutter/material.dart';

import '../theme/accent.dart';

/// Clean accent spinner indicator.
class PzSpinner extends StatelessWidget {
  const PzSpinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 2.5,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = PzAccent.of(context);
    final indicatorColor = color ?? accent.base;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.square,
          valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
        ),
      ),
    );
  }
}
