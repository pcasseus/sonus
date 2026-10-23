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
  Completer<void>? _drained;

  int get activeMutations => _activeMutations;
  bool get isRestoreRequested => _restoreRequested;

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

    _restoreRequested = true;

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
