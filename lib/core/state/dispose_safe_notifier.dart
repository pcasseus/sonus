import 'package:flutter/foundation.dart';

/// A [ChangeNotifier] whose late notifications are ignored once disposed.
///
/// Screens dispose their controllers when they leave the tree (for example
/// a tab page the shell no longer keeps), while a load or refresh the
/// controller started may still be awaiting its data. When that work
/// finishes it notifies a controller nobody listens to any more; a plain
/// ChangeNotifier asserts ("used after being disposed"). With this mixin
/// the late notification is dropped, so the finished work is simply
/// discarded. [isDisposed] lets long work stop early.
mixin DisposeSafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
