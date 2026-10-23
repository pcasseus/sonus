/// Coordinates whole synchronization runs with operations that must not
/// overlap cloud synchronization, such as restoring a library backup.
///
/// A guard either runs [run] to completion while preventing such
/// operations from starting, or rejects it with [SyncHeldForRecovery].
abstract interface class SyncRunGuard {
  Future<T> guard<T>(Future<T> Function() run);
}

enum SyncHoldReason {
  /// A restore is in progress on this device.
  restoreInProgress,

  /// A restored library is awaiting a consistency assessment.
  assessmentRequired,

  /// The persisted hold state could not be read, so sync stays paused.
  holdStateUnreadable,

  /// The startup check for interrupted restores has not finished yet.
  recoveryCheckPending,

  /// The startup check for interrupted restores failed; sync stays paused.
  recoveryCheckFailed,
}

/// Synchronization was not started because recovery holds it paused.
///
/// No account attachment, push, or pull work was performed.
class SyncHeldForRecovery implements Exception {
  const SyncHeldForRecovery(this.reason);

  final SyncHoldReason reason;

  @override
  String toString() => 'SyncHeldForRecovery(${reason.name})';
}
