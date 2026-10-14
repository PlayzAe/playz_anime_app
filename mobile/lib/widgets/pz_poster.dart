import 'package:flutter/material.dart' hide Ink;

import '../theme/tokens.dart';
import 'pz_image.dart';
import 'pz_progress.dart';

/// The 460/650 art poster card.
/// Designed with Flex and AspectRatio so it scales across any screen width.
class PzPoster extends StatelessWidget {
  const PzPoster({
    super.key,
    required this.title,
    required this.imageUrl,
    this.meta,
    this.badge,
    this.rank,
    this.progress,
    this.width,
    this.aspect = Metrics.posterAspect,
    this.onTap,
  });

  final String title;
  final String imageUrl;
  final String? meta;
  final String? badge;
  final int? rank;
  final double? progress;
  final double? width;
  final double aspect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget card = LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PzImage(
                    url: imageUrl,
                    radius: const BorderRadius.all(Radius.circular(Radii.frame)),
                    fit: BoxFit.cover,
                  ),
                  if (rank != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Ink.ink0.withAlpha(210),
                          borderRadius: BorderRadius.circular(Radii.r1),
                          border: Border.all(color: Lines.line2, width: 0.5),
                        ),
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Paper.paper,
                          ),
                        ),
                      ),
                    ),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Ink.ink0.withAlpha(210),
                          borderRadius: BorderRadius.circular(Radii.r1),
                          border: Border.all(color: Lines.line2, width: 0.5),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Paper.paper2,
                          ),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.frame)),
                        child: PzProgress(value: progress!.clamp(0.0, 1.0)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Type.posterTitle.copyWith(color: Paper.paper),
            ),
            if (meta != null && meta!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.posterMeta.copyWith(color: Paper.paper3),
              ),
            ],
          ],
        );
      },
    );

    if (width != null) {
      card = SizedBox(width: width, child: card);
    }

    if (onTap != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}
