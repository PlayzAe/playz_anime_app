import 'package:flutter/material.dart' hide Ink;

import '../theme/tokens.dart';
import 'pz_icon_button.dart';

/// A bottom sheet on mobile, centered modal on tablets.
/// Ported from PlayzAnime's desktop Modal primitive.
class PzModal extends StatelessWidget {
  const PzModal({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.onClose,
    this.bare = false,
    this.maxWidth = 560,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final bool bare;
  final double maxWidth;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    List<Widget>? actions,
    bool bare = false,
    double maxWidth = 560,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PzModal(
        title: title,
        actions: actions,
        bare: bare,
        maxWidth: maxWidth,
        onClose: () => Navigator.of(ctx).pop(),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: const BoxDecoration(
        color: Ink.ink1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.r3)),
        border: Border(
          top: BorderSide(color: Lines.line, width: 1),
          left: BorderSide(color: Lines.line, width: 1),
          right: BorderSide(color: Lines.line, width: 1),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Paper.paper4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (!bare) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, 8, Gap.gutter, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Type.sectionTitle.copyWith(color: Paper.paper),
                    ),
                  ),
                  ...?actions,
                  PzIconButton(
                    icon: 'close',
                    size: 18,
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Lines.line),
          ],
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Gap.gutter, vertical: 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
