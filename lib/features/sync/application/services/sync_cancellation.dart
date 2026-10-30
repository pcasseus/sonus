import 'dart:async';

/// A sync run was stopped at a safe point: between whole units of work
/// (an outbox entry with its acknowledgement, a cloud record with its
/// cursor, an archive record with its state), never inside one. Nothing
/// of the stopped unit was written; unsent changes stay in the outbox.
class SyncCancelled implements Exception {
  const SyncCancelled(this.reason);

  final String reason;

  @override
  String toString() => 'SyncCancelled($reason)';
}

/// Cooperative cancellation for one sync run (SN-50 #23).
///
/// The controller runs the service inside [run]; the service and its
/// processors call [checkpoint] only at safe boundaries. Outside a run
/// [checkpoint] does nothing, so code paths used without a controller (and
/// test doubles) are unaffected.
class SyncCancellation {
  SyncCancellation(this.userId);

  /// The account this run syncs.
  final String userId;

  static final Object _zoneKey = Object();

  String? _reason;

  bool get isCancelled => _reason != null;

  /// Why the run was stopped (timeout, sign-out, account switch, dispose).
  String? get reason => _reason;

  /// Stops the run at its next safe point. Later calls keep the first reason.
  void cancel(String reason) => _reason ??= reason;

  /// Runs [body] with this cancellation active for everything it starts.
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  /// The cancellation of the run this code belongs to, if any.
  static SyncCancellation? get current =>
      Zone.current[_zoneKey] as SyncCancellation?;

  /// Throws [SyncCancelled] if the current run was cancelled. Call only
  /// between units of work, or as the first or last statement inside a
  /// unit's own transaction (where throwing rolls the unit back).
  static void checkpoint() {
    final cancellation = current;
    final reason = cancellation?._reason;
    if (reason != null) throw SyncCancelled(reason);
  }
}
