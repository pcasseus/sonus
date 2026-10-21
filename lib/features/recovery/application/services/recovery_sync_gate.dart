import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../sync/application/services/sync_run_guard.dart';
import '../models/recovery_sync_hold.dart';
import 'recovery_sync_hold_store.dart';

/// Thrown when a restore cannot obtain exclusive access to the library.
class RecoveryGateUnavailable implements Exception {
  const RecoveryGateUnavailable(this.message);

  final String message;

  @override
  String toString() => 'RecoveryGateUnavailable: $message';
}

/// Serializes cloud synchronization against backup restoration.
///
/// * While a restore owns the gate, every new sync run is rejected
///   synchronously, before any await, so no run can slip in.
/// * Before a restore proceeds, the gate persists the hold and then waits
///   for runs that were already active to finish.
/// * After the restore, the persisted hold keeps rejecting runs, across
///   restarts, until recovery explicitly releases it.
class RecoverySyncGate implements SyncRunGuard {
  RecoverySyncGate({
    required this.holdStore,
    this.drainTimeout = const Duration(minutes: 2),
  });

  /// The gate shared by sync and recovery in the running app.
  static final RecoverySyncGate application = RecoverySyncGate(
    holdStore: RecoverySyncHoldStore(directory: applicationRecoveryDirectory),
  );

  final RecoverySyncHoldStore holdStore;
  final Duration drainTimeout;

  int _activeRuns = 0;
  bool _restoreActive = false;
  Completer<void>? _drained;

  bool get isRestoreActive => _restoreActive;

  int get activeSyncRuns => _activeRuns;

  @override
  Future<T> guard<T>(Future<T> Function() run) async {
    // Checked and counted synchronously; see class documentation.
    if (_restoreActive) {
      throw const SyncHeldForRecovery(SyncHoldReason.restoreInProgress);
    }

    _activeRuns++;

    try {
      final state = await holdStore.read();

      if (_restoreActive) {
        throw const SyncHeldForRecovery(SyncHoldReason.restoreInProgress);
      }

      switch (state) {
        case NoRecoverySyncHold():
          break;
        case ActiveRecoverySyncHold(:final hold):
          throw SyncHeldForRecovery(
            hold.phase == RecoverySyncHoldPhase.restoring
                ? SyncHoldReason.restoreInProgress
                : SyncHoldReason.assessmentRequired,
          );
        case UnreadableRecoverySyncHold():
          throw const SyncHeldForRecovery(SyncHoldReason.holdStateUnreadable);
      }

      return await run();
    } finally {
      _activeRuns--;

      if (_activeRuns == 0) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  /// Claims the gate for a restore.
  ///
  /// [buildHold] receives the previously persisted state and returns the
  /// hold to persist. On success the hold is durable and no sync run is
  /// active. On failure the previous state is reinstated and the gate is
  /// released again.
  Future<RecoverySyncHoldState> beginRestore(
    RecoverySyncHold Function(RecoverySyncHoldState previous) buildHold,
  ) async {
    if (_restoreActive) {
      throw const RecoveryGateUnavailable('A restore is already running.');
    }

    _restoreActive = true;

    RecoverySyncHoldState? previous;

    try {
      previous = await holdStore.read();
      await holdStore.write(buildHold(previous));

      if (_activeRuns > 0) {
        final drained = _drained ??= Completer<void>();

        await drained.future.timeout(
          drainTimeout,
          onTimeout: () => throw const RecoveryGateUnavailable(
            'Cloud synchronization is still running.',
          ),
        );
      }

      return previous;
    } catch (_) {
      try {
        if (previous != null) {
          await holdStore.restore(previous);
        }
      } finally {
        _restoreActive = false;
      }

      rethrow;
    }
  }

  /// Ends the restore's exclusive ownership. The persisted hold, if any,
  /// continues to govern synchronization.
  void endRestore() {
    _restoreActive = false;
  }
}

/// `<application support>/sonus/recovery`, next to managed artwork.
Future<Directory> applicationRecoveryDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(path.join(support.path, 'sonus', 'recovery'));
}
