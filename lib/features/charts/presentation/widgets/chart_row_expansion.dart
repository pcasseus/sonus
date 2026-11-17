import 'package:flutter/widgets.dart';

/// Which chart row is expanded (App Update 1.3 Chart Studio): at most one
/// per chart view. Held above the list, so a row keeps its state while it
/// scrolls out of view and while Song Stats is open over the page.
///
/// Rows listen to [open] themselves, so expanding one rebuilds only the row
/// that opens and the row that closes, never the whole chart.
class ChartRowExpansion extends InheritedWidget {
  const ChartRowExpansion._({required this.open, required super.child});

  /// The expanded row's entity id, or null.
  final ValueNotifier<String?> open;

  static ChartRowExpansion? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChartRowExpansion>();

  @override
  bool updateShouldNotify(ChartRowExpansion oldWidget) =>
      open != oldWidget.open;
}

/// Owns the expansion for one chart view. A different [view] (another
/// chart, board or week) starts with every row closed.
class ChartRowExpansionHost extends StatefulWidget {
  const ChartRowExpansionHost({
    super.key,
    required this.view,
    required this.child,
  });

  final String view;
  final Widget child;

  @override
  State<ChartRowExpansionHost> createState() => _ChartRowExpansionHostState();
}

class _ChartRowExpansionHostState extends State<ChartRowExpansionHost> {
  final ValueNotifier<String?> _open = ValueNotifier<String?>(null);

  @override
  void didUpdateWidget(ChartRowExpansionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) _open.value = null;
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChartRowExpansion._(open: _open, child: widget.child);
}
