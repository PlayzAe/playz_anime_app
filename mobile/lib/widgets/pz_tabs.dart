import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// One entry in a [PzTabs] row.
class PzTab<T> {
  const PzTab(this.value, this.label, {this.count});

  final T value;
  final String label;

  /// An optional number after the label — the library's "Watching 12".
  ///
  /// It stays `paper-3` even on the selected tab: the underline is the only
  /// selected cue the design allows here, and a bright count would fight it.
  final int? count;
}

/// The design system's tab row.
///
/// Forty pixels tall, a 22px gap between tabs, one hairline under the whole
/// strip, and the selected tab marked by a 2px paper bar sitting *on* that
/// hairline (the desktop's `bottom: -1px`) rather than a filled pill. The strip
/// scrolls sideways once the tabs outgrow the phone; [trailing] is pinned
/// outside that scroll so a trailing action never scrolls away with the tabs.
class PzTabs<T> extends StatelessWidget {
  const PzTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.trailing,
  });

  final List<PzTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget? trailing;

  /// The tab band, and the hairline that closes it.
  static const double _band = 40;
  static const double _rule = 1;

  /// `.tabs { gap: 22px }`
  static const double _gap = 22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _band + _rule,
      child: Stack(
        children: [
          // Painted first, so the selected tab's underline can sit over it.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _rule,
            child: ColoredBox(color: Lines.line),
          ),
          Row(
            children: [
              Expanded(
                child: FocusTraversalGroup(
                  // The row is one traversal unit: Tab lands on the selected
                  // tab, the arrow keys move within it, and they wrap here
                  // instead of walking off into the shell's other controls.
                  child: FocusScope(
                    debugLabel: 'PzTabs',
                    child: ScrollConfiguration(
                      // `.tabs::-webkit-scrollbar { display: none }`
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Builder(
                          // Below the scope, so the arrow handler can reach the
                          // scope it has to move focus inside of.
                          builder: (inner) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < tabs.length; i++) ...[
                                if (i > 0) const SizedBox(width: _gap),
                                _PzTabButton<T>(
                                  tab: tabs[i],
                                  selected: tabs[i].value == selected,
                                  onTap: () => onChanged(tabs[i].value),
                                  onStep: (forward) => _step(inner, forward),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  // The row is a pixel taller than the band so the underline can
                  // reach the rule; keep the trailing widget on the band.
                  padding: const EdgeInsets.only(left: 12, bottom: _rule),
                  child: trailing!,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Moves the selection one tab, wrapping, and takes the keyboard focus with
  /// it — the desktop's roving `tabIndex`, where only the current tab is a stop.
  void _step(BuildContext context, bool forward) {
    final from = tabs.indexWhere((t) => t.value == selected);
    if (from < 0 || tabs.length < 2) return;
    final next = tabs[(from + (forward ? 1 : -1) + tabs.length) % tabs.length];
    onChanged(next.value);

    // After the frame: the tab that just became current is the only one that
    // still accepts focus, so the walk lands on it and never on a neighbour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final scope = FocusScope.of(context);
      final moved = forward ? scope.nextFocus() : scope.previousFocus();
      if (!moved) return;
      final target = FocusManager.instance.primaryFocus?.context;
      // A tab past the edge has to come into view, the way `.focus()` scrolls
      // the browser's strip.
      if (target != null) {
        Scrollable.ensureVisible(target, duration: Motion.fast, curve: Motion.ease);
      }
    });
  }
}

class _PzTabButton<T> extends StatefulWidget {
  const _PzTabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onStep,
  });

  final PzTab<T> tab;
  final bool selected;
  final VoidCallback onTap;

  /// `true` for the tab to the right of this one, `false` for the one to the
  /// left; [PzTabs] does the wrapping.
  final ValueChanged<bool> onStep;

  @override
  State<_PzTabButton<T>> createState() => _PzTabButtonState<T>();
}

class _PzTabButtonState<T> extends State<_PzTabButton<T>> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // `.tabs button` is paper-3, its hover is paper-2, and selected is paper.
    // A finger cannot see a hover, so the press lifts straight to paper.
    final lit = widget.selected || _pressed || _focused;
    final colour = lit ? Paper.paper : (_hovered ? Paper.paper2 : Paper.paper3);

    final label = Text(
      widget.tab.label,
      maxLines: 1,
      softWrap: false,
      style: Type.label.copyWith(color: colour),
    );
    final count = widget.tab.count;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: count == null ? widget.tab.label : '${widget.tab.label}, $count',
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Focus(
          canRequestFocus: widget.selected,
          onFocusChange: (has) => setState(() => _focused = has),
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: PzTabs._band,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              label,
                              if (count != null) ...[
                                const SizedBox(width: 7),
                                // `.tab-count` — 12/600, and `.num`: a count
                                // that ticks must not shuffle the ones beside it.
                                Text(
                                  '$count',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: Type.posterMeta.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Paper.paper3,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // The slice that puts the underline's foot on the rule.
                      const SizedBox(height: PzTabs._rule),
                    ],
                  ),
                  if (widget.selected)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 2,
                      child: ColoredBox(color: Paper.paper),
                    ),
                  // The desktop's `:focus-visible` outline. It sits on the tab's
                  // own box rather than 2px outside it: anything outside would be
                  // clipped by the scrollable that has to keep the strip narrow.
                  if (_focused)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: PzTabs._rule,
                      height: PzTabs._band,
                      child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: Paper.paper, width: 2)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onStep(true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onStep(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
