import 'package:flutter/material.dart' hide Ink;

import '../theme/tokens.dart';
import 'pz_button.dart';
import 'pz_icon.dart';

/// Error state with retry action.
class PzError extends StatelessWidget {
  const PzError({
    super.key,
    required this.error,
    this.title = 'Something went wrong',
    this.onRetry,
  });

  final Object error;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Ink.ink1,
                shape: BoxShape.circle,
                border: Border.all(color: Tone.bad.withAlpha(80), width: 1),
              ),
              child: const Center(
                child: PzIcon('info', size: 28, color: Tone.bad),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Type.sectionTitle.copyWith(color: Paper.paper),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Type.caption.copyWith(color: Paper.paper3),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              PzButton(
                label: 'Retry',
                icon: 'reload',
                onPressed: onRetry,
                size: PzButtonSize.sm,
                kind: PzButtonKind.solid,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
