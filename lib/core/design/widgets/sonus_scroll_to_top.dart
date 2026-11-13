import 'dart:async';

import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// A floating "Back to top" button over a long scrolling page, shown once
/// the page is scrolled well down (Charts 2.0 C1; App Update 1.2 BUG-04
/// brings it to Tracks).
///
/// [child] is the page's scroll view, driven by [controller]. The button
/// sits inside the page, which ends above the mini-player, so it never
/// covers it. It only scrolls: filters, search text and selection are
/// untouched. Reduce motion jumps instead of animating.
///
/// Whether it shows follows the scroll offset, and also the scroll view's
/// metrics, so content that changes without a scroll (another board, a
/// filter, a search) updates it too. Only the page's own scroll view
/// counts, not lists nested inside it.
class SonusScrollToTop extends StatefulWidget {
  const SonusScrollToTop({
    super.key,
    required this.controller,
    required this.child,
    this.buttonKey = const ValueKey<String>('scroll-to-top'),
    this.end = 16,
    this.bottom = 16,
    this.showAfter = defaultShowAfter,
  });

  /// How far down (logical pixels) the page must be for the button.
  static const double defaultShowAfter = 800;

  final ScrollController controller;
  final Widget child;
  final Key buttonKey;

  /// Distance from the end edge, for example to clear an index rail.
  final double end;
  final double bottom;
  final double showAfter;

  @override
  State<SonusScrollToTop> createState() => _SonusScrollToTopState();
}

class _SonusScrollToTopState extends State<SonusScrollToTop> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(SonusScrollToTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _update();
    }
  }

  void _update() {
    final controller = widget.controller;
    final show =
        controller.hasClients &&
        controller.positions.length == 1 &&
        controller.offset > widget.showAfter;
    if (show != _show && mounted) setState(() => _show = show);
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _update();
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) _update();
    return false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _toTop() {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final motion = SonusTheme.of(context).motion;
    if (motion.reduced) {
      controller.jumpTo(0);
    } else {
      unawaited(
        controller.animateTo(0, duration: motion.long, curve: motion.curve),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = SonusTheme.of(context).motion;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: _onMetrics,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        PositionedDirectional(
          end: widget.end,
          bottom: widget.bottom,
          child: IgnorePointer(
            ignoring: !_show,
            child: ExcludeSemantics(
              excluding: !_show,
              child: AnimatedOpacity(
                opacity: _show ? 1 : 0,
                duration: motion.short,
                child: FloatingActionButton.small(
                  key: widget.buttonKey,
                  heroTag: null,
                  tooltip: 'Back to top',
                  onPressed: _show ? _toTop : null,
                  child: const Icon(Icons.vertical_align_top_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
