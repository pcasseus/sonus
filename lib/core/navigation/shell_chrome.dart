import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Which destination of the app shell may take the whole screen, and
/// whether the shell's top bar (title, actions and tabs) is shown.
///
/// A destination asks for the screen by placing a [ShellImmersive] in its
/// page (the Artist Roster does, UI redesign L2). While that destination is
/// the current one, the shell hides its top bar; [reveal] brings the bar
/// back over the page, so the rest of Sonus is always one tap away, and
/// [conceal] or choosing a destination hides it again. The mini-player is
/// not the shell's and is never affected.
class ShellChromeController extends ChangeNotifier {
  ShellChromeController({required this._current});

  Object _current;
  final Map<Object, int> _requests = {};
  bool _revealed = false;

  /// The destination on screen.
  Object get current => _current;

  /// Whether the current destination takes the whole screen.
  bool get immersive => (_requests[_current] ?? 0) > 0;

  /// Whether the top bar is shown over an immersive destination.
  bool get revealed => immersive && _revealed;

  /// Whether the shell lays its top bar out above the page.
  bool get showsBar => !immersive;

  void setCurrent(Object destination) {
    if (destination == _current) return;
    _current = destination;
    _revealed = false;
    notifyListeners();
  }

  /// Shows the top bar over the current immersive destination.
  void reveal() {
    if (!immersive || _revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// Hides the top bar shown by [reveal].
  void conceal() {
    if (!_revealed) return;
    _revealed = false;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Requests arrive after a frame, possibly once the shell has gone.
  void _request(Object destination) {
    if (_disposed) return;
    final before = immersive;
    _requests[destination] = (_requests[destination] ?? 0) + 1;
    if (immersive != before) notifyListeners();
  }

  void _release(Object destination) {
    if (_disposed) return;
    final before = immersive;
    final count = (_requests[destination] ?? 0) - 1;
    if (count > 0) {
      _requests[destination] = count;
    } else {
      _requests.remove(destination);
    }
    if (!immersive) _revealed = false;
    if (immersive != before) notifyListeners();
  }

  /// What a [ShellImmersive] does when shown, for tests.
  @visibleForTesting
  void debugRequest(Object destination) => _request(destination);

  /// What a [ShellImmersive] does when it goes, for tests.
  @visibleForTesting
  void debugRelease(Object destination) => _release(destination);
}

/// Tells the pages of the app shell which destination they are and gives
/// them the shell's [ShellChromeController].
class ShellChromeScope extends InheritedWidget {
  const ShellChromeScope({
    super.key,
    required this.controller,
    required this.destination,
    required super.child,
  });

  final ShellChromeController controller;
  final Object destination;

  static ShellChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellChromeScope>();

  /// Shows the shell's top bar over this destination; null outside a shell.
  static VoidCallback? revealOf(BuildContext context) =>
      maybeOf(context)?.controller.reveal;

  @override
  bool updateShouldNotify(ShellChromeScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      destination != oldWidget.destination;
}

/// While shown, its destination takes the whole screen: the shell hides its
/// top bar whenever that destination is current. Outside a shell it does
/// nothing.
class ShellImmersive extends StatefulWidget {
  const ShellImmersive({super.key, required this.child});

  final Widget child;

  @override
  State<ShellImmersive> createState() => _ShellImmersiveState();
}

class _ShellImmersiveState extends State<ShellImmersive> {
  (ShellChromeController, Object)? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ShellChromeScope.maybeOf(context);
    final wanted = scope == null ? null : (scope.controller, scope.destination);
    if (wanted == _held) return;
    final previous = _held;
    _held = wanted;
    // Never during a build: the shell rebuilds when this changes.
    _afterFrame(() {
      if (previous != null) previous.$1._release(previous.$2);
      if (wanted != null) wanted.$1._request(wanted.$2);
    });
  }

  @override
  void dispose() {
    final held = _held;
    if (held != null) _afterFrame(() => held.$1._release(held.$2));
    super.dispose();
  }

  static void _afterFrame(VoidCallback action) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => action())
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
