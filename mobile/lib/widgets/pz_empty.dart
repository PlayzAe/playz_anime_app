import 'package:flutter/material.dart' hide Ink;

import '../theme/icons.dart';
import '../theme/tokens.dart';
import 'pz_button.dart';
import 'pz_icon.dart';

/// Clean empty state with icon, title, description, and optional action.
class PzEmpty extends StatelessWidget {
  const PzEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = 'library',
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconName icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
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
                border: Border.all(color: Lines.line, width: 1),
              ),
              child: Center(
                child: PzIcon(icon, size: 28, color: Paper.paper3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Type.sectionTitle.copyWith(color: Paper.paper),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Type.bodySm.copyWith(color: Paper.paper3),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              PzButton(
                label: actionLabel!,
                onPressed: onAction,
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
