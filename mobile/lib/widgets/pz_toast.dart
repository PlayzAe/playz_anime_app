import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

enum ToastTone { info, error, success }

class ToastAction {
  const ToastAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

class ToastItem {
  ToastItem({
    required this.id,
    required this.text,
    this.tone = ToastTone.info,
    this.action,
  });

  final Object id;
  final String text;
  final ToastTone tone;
  final ToastAction? action;
}

/// App-wide toast notification queue.
class PzToasts extends ChangeNotifier {
  PzToasts._();
  static final PzToasts i = PzToasts._();

  final List<ToastItem> _items = [];
  List<ToastItem> get items => List.unmodifiable(_items);

  int _seq = 0;

  void show(String text, {ToastTone tone = ToastTone.info, ToastAction? action}) {
    final id = ++_seq;
    final item = ToastItem(id: id, text: text, tone: tone, action: action);
    _items.add(item);
    notifyListeners();

    final duration = action != null
        ? const Duration(milliseconds: 6000)
        : const Duration(milliseconds: 3400);
    Timer(duration, () {
      dismiss(id);
    });
  }

  void dismiss(Object id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _items.removeAt(idx);
      notifyListeners();
    }
  }
}

/// Host widget that renders the current toast notifications atop its child.
class PzToastHost extends StatelessWidget {
  const PzToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PzToasts.i,
      builder: (context, _) {
        final items = PzToasts.i.items;
        return Stack(
          children: [
            child,
            if (items.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final toast in items)
                        _ToastCard(key: ValueKey(toast.id), item: toast),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.item});

  final ToastItem item;

  @override
  Widget build(BuildContext context) {
    final accent = PzAccent.of(context);
    final bg = switch (item.tone) {
      ToastTone.error => const Color(0xFFE5484D),
      ToastTone.success => const Color(0xFF46A758),
      ToastTone.info => PzInk.ink2,
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.frame),
        border: Border.all(color: Lines.line),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              item.text,
              style: const TextStyle(
                color: Paper.paper,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (item.action != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                PzToasts.i.dismiss(item.id);
                item.action!.onPressed();
              },
              child: Text(
                item.action!.label,
                style: TextStyle(
                  color: accent.base,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}