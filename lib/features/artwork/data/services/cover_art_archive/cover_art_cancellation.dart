import 'dart:async';

class CoverArtCancelledException implements Exception {
  const CoverArtCancelledException();

  @override
  String toString() => 'CoverArtCancelledException: Download cancelled.';
}

class CoverArtCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void throwIfCancelled() {
    if (isCancelled) {
      throw const CoverArtCancelledException();
    }
  }

  void Function() onCancel(void Function() callback) {
    if (isCancelled) {
      callback();
      return () {};
    }

    _listeners.add(callback);

    return () {
      _listeners.remove(callback);
    };
  }

  void cancel() {
    if (isCancelled) {
      return;
    }

    _cancelled.complete();

    final callbacks = List<void Function()>.of(_listeners);
    _listeners.clear();

    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        // One listener must not prevent other cancellations.
      }
    }
  }
}
