import 'dart:async';

class LibraryMutationUnavailable implements Exception {
  const LibraryMutationUnavailable(this.message);

  final String message;

  @override
  String toString() => 'LibraryMutationUnavailable: $message';
}

/// Coordinates ordinary local mutations with an exclusive restore.
///
/// This class intentionally does not access SQLite.
class LibraryMutationCoordinator {
  LibraryMutationCoordinator({this.drainTimeout = const Duration(minutes: 2)});

  final Duration drainTimeout;

  int _activeMutations = 0;
  bool _restoreRequested = false;
  int _restoreGeneration = 0;
  Completer<void>? _drained;

  int get activeMutations => _activeMutations;
  bool get isRestoreRequested => _restoreRequested;

  /// Advances, and never goes back, each time an exclusive restore is
  /// requested, whatever its outcome.
  ///
  /// Work that reads the library over several asynchronous steps captures it
  /// first; a different value before a write means a restore may have
  /// replaced what it read.
  int get restoreGeneration => _restoreGeneration;

  Future<T> runMutation<T>(Future<T> Function() action) async {
    if (_restoreRequested) {
      throw const LibraryMutationUnavailable(
        'Library restoration is in progress.',
      );
    }

    _activeMutations++;

    try {
      return await action();
    } finally {
      _activeMutations--;

      if (_activeMutations == 0) {
        final drained = _drained;
        _drained = null;
        drained?.complete();
      }
    }
  }

  Future<T> runExclusiveRestore<T>(Future<T> Function() action) async {
    if (_restoreRequested) {
      throw const LibraryMutationUnavailable(
        'Another restoration is already in progress.',
      );
    }

    // Advanced in the same synchronous step that closes admission, so no
    // mutation can be admitted between the two.
    _restoreRequested = true;
    _restoreGeneration++;

    try {
      if (_activeMutations > 0) {
        final drained = _drained ??= Completer<void>();

        await drained.future.timeout(
          drainTimeout,
          onTimeout: () => throw const LibraryMutationUnavailable(
            'Active library operations did not finish in time.',
          ),
        );
      }

      return await action();
    } finally {
      _restoreRequested = false;
    }
  }
}
