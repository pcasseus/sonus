import 'package:flutter/widgets.dart';

/// Rebuilds the application below it from scratch, so every scope reloads
/// its data. Used after a backup restore replaced the library.
class AppRestartScope extends StatefulWidget {
  const AppRestartScope({super.key, required this.child});

  final Widget child;

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_AppRestartScopeState>()?._restart();
  }

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  int _generation = 0;

  void _restart() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<int>(_generation),
      child: widget.child,
    );
  }
}
