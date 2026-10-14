import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A responsive grid of poster cards using LayoutBuilder and Flex.
/// Computes column count dynamically so it fits any mobile viewport width without overflow.
class PzPosterGrid extends StatelessWidget {
  const PzPosterGrid({
    super.key,
    required this.children,
    this.padding,
    this.minWidth = Metrics.posterMin,
    this.aspect = Metrics.posterAspect,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double minWidth;
  final double aspect;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth -
            ((padding?.horizontal ?? (Gap.gutter * 2)));
        // Dynamically compute column count: 2 columns min, scaling up with width
        final cols = (availableWidth / (minWidth + Metrics.posterGapX)).floor().clamp(2, 6);
        // Card child aspect ratio = posterAspect adjusted for title and meta space (~54px)
        final itemWidth = (availableWidth - ((cols - 1) * Metrics.posterGapX)) / cols;
        final itemHeight = (itemWidth / aspect) + 54;
        final childAspect = itemWidth / itemHeight;

        return GridView.builder(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: Gap.gutter, vertical: 12),
          shrinkWrap: shrinkWrap,
          physics: physics ?? const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: Metrics.posterGapX,
            mainAxisSpacing: Metrics.posterGapY,
            childAspectRatio: childAspect,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}
