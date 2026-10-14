import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A horizontal scrolling shelf with a section header.
/// Ported from PlayzAnime's desktop Shelf component.
class PzShelf extends StatelessWidget {
  const PzShelf({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.action,
    this.onSeeAll,
    this.cardWidth = Metrics.shelfCard,
    this.cardAspect = Metrics.posterAspect,
  });

  final String title;
  final List<Widget> children;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final double cardAspect;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    // Height = cardWidth / aspect + room for 2-line title + meta text + gaps
    final imageHeight = cardWidth / cardAspect;
    final totalHeight = imageHeight + 54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Type.sectionTitle.copyWith(color: Paper.paper),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Type.caption.copyWith(color: Paper.paper3),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null)
                action!
              else if (onSeeAll != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSeeAll,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'See all',
                      style: TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Paper.paper2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: totalHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: Metrics.shelfGap),
            itemBuilder: (context, index) => SizedBox(
              width: cardWidth,
              child: children[index],
            ),
          ),
        ),
      ],
    );
  }
}
