import 'package:flutter/widgets.dart';

/// A horizontal rail that starts at its first item whenever it is entered
/// (App Update 1.3 follow-up).
///
/// Why it exists: a horizontal scroll view without its own controller keeps
/// its offset in [PageStorage] under the nearest [PageStorageKey]. On most
/// pages that is the page's own vertical scroll, shared by every rail on
/// it, so a rail could reopen at the page's vertical offset (mid-rail or at
/// the end), and one rail's scrolling overwrote another's.
///
/// The rail owns a controller that never reads or writes [PageStorage]
/// (`keepScrollOffset: false`), so:
/// - a fresh page entry starts at the first item, aligned left;
/// - [identity] names what the rail shows (an artist and section, an album,
///   a set of items). A different identity is a different rail: its scroll
///   position is created anew, at the first item, on its first frame, with
///   no jump from an old offset;
/// - returning from a detail page keeps the position, because the parent
///   page and this rail stay alive underneath the detail route;
/// - an ordinary rebuild or refresh with the same identity never moves it.
class SonusHorizontalRail extends StatefulWidget {
  const SonusHorizontalRail({
    super.key,
    required this.identity,
    required this.builder,
  });

  /// What the rail shows; a different value starts it at its first item.
  final Object identity;

  /// Builds the horizontal scroll view with the rail's [ScrollController].
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SonusHorizontalRail> createState() => _SonusHorizontalRailState();
}

class _SonusHorizontalRailState extends State<SonusHorizontalRail> {
  late ScrollController _controller = _fresh();

  static ScrollController _fresh() => ScrollController(keepScrollOffset: false);

  @override
  void didUpdateWidget(SonusHorizontalRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      final old = _controller;
      _controller = _fresh();
      // Detached by the rebuild below, which keys the scroll view anew.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<Object>(widget.identity),
      child: widget.builder(context, _controller),
    );
  }
}
