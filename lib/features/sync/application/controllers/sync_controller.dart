import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../../data/services/sync_status_store.dart';
import '../models/sync_failure.dart';
import '../services/cloud_library_first_link_guard.dart';
import '../services/sync_run_guard.dart';
import '../services/sync_service.dart';

enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  accountConflict,

  /// Paused by backup recovery; no sync work was attempted.
  recoveryHold,

  /// The account already has a cloud library and this device has never
  /// synced with it; nothing moves until the person chooses.
  awaitingCloudChoice,
}

class SyncController extends ChangeNotifier {
  SyncController({
    required SyncService service,
    SyncStatusStore? statusStore,
    SyncFailureClassifier classifyFailure = classifySyncFailure,
    Future<void> Function(String userId)? grantCloudLibrary,
  }) : this._(
         synchronize: service.synchronize,
         statusStore: statusStore ?? SyncStatusStore(),
         countPending: service.pendingCount,
         classifyFailure: classifyFailure,
         grantCloudLibrary: grantCloudLibrary,
       );

  @visibleForTesting
  SyncController.forTesting({
    required Future<SyncRunResult> Function(String userId) synchronize,
    SyncStatusStore? statusStore,
    Future<int> Function(String userId)? countPending,
    SyncFailureClassifier classifyFailure = classifySyncFailure,
    Future<void> Function(String userId)? grantCloudLibrary,
  }) : this._(
         synchronize: synchronize,
         statusStore:
             statusStore ??
             SyncStatusStore.forTesting(
               getString: (_) async => null,
               setString: (_, _) async {},
             ),
         countPending: countPending,
         classifyFailure: classifyFailure,
         grantCloudLibrary: grantCloudLibrary,
       );

  SyncController._({
    required this._synchronize,
    required this._statusStore,
    required this._countPending,
    required this._classifyFailure,
    required this._grantCloudLibrary,
  });

  final Future<SyncRunResult> Function(String userId) _synchronize;
  final SyncStatusStore _statusStore;

  /// Reads the local outbox, so pending work is shown before any run.
  final Future<int> Function(String userId)? _countPending;
  final SyncFailureClassifier _classifyFailure;
  final Future<void> Function(String userId)? _grantCloudLibrary;

  Future<void> _pending = Future<void>.value();

  /// A run waiting behind the current one. Further requests join it, so a
  /// burst of triggers or taps runs at most once more.
  Future<bool>? _queued;
  String? _queuedUserId;

  SyncFailureKind? _failureKind;

  SyncStatus _status = SyncStatus.idle;
  String? _currentUserId;
  DateTime? _lastSuccessfulSync;
  int _pendingChanges = 0;
  Object? _lastError;
  SyncRunResult? _lastResult;
  bool _retryPending = false;

  int _activationGeneration = 0;

  SyncStatus get status => _status;

  String? get currentUserId => _currentUserId;

  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  int get pendingChanges => _pendingChanges;

  Object? get lastError => _lastError;

  SyncRunResult? get lastResult => _lastResult;

  bool get retryPending => _retryPending;

  /// Why the last attempt failed; null unless [status] is error.
  SyncFailureKind? get failureKind => _failureKind;

  bool get isSyncing => _status == SyncStatus.syncing;

  bool get hasError =>
      _status == SyncStatus.error || _status == SyncStatus.accountConflict;

  bool get hasAccountConflict => _status == SyncStatus.accountConflict;

  bool get isRecoveryHeld => _status == SyncStatus.recoveryHold;

  bool get isAwaitingCloudChoice => _status == SyncStatus.awaitingCloudChoice;

  /// The person chose to bring the account's cloud library onto this
  /// device: records the choice and syncs.
  Future<bool> bringCloudLibrary() async {
    final userId = _currentUserId;
    final grant = _grantCloudLibrary;
    if (userId == null || grant == null) return false;
    await grant(userId);
    return synchronize(userId);
  }

  SyncHoldReason? get recoveryHoldReason => switch (_lastError) {
    SyncHeldForRecovery(:final reason) => reason,
    _ => null,
  };

  Future<void> activateUser(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (_currentUserId == normalizedUserId) {
      return;
    }

    final generation = ++_activationGeneration;

    _currentUserId = normalizedUserId;
    _status = SyncStatus.idle;
    _lastSuccessfulSync = null;
    _pendingChanges = 0;
    _lastError = null;
    _lastResult = null;
    _retryPending = false;
    _failureKind = null;
    notifyListeners();

    DateTime? restored;

    try {
      restored = await _statusStore.getLastSuccessfulSync(normalizedUserId);
    } catch (error) {
      _log('Could not read the last sync time', error);
    }

    final pending = await _readPendingCount(normalizedUserId);

    if (generation != _activationGeneration ||
        _currentUserId != normalizedUserId) {
      return;
    }

    _lastSuccessfulSync = restored;
    _pendingChanges = pending ?? _pendingChanges;
    notifyListeners();
  }

  Future<int?> _readPendingCount(String userId) async {
    final countPending = _countPending;
    if (countPending == null) return null;

    try {
      return await countPending(userId);
    } catch (error) {
      _log('Could not count pending changes', error);
      return null;
    }
  }

  Future<bool> synchronize(String userId) {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      return Future<bool>.error(
        ArgumentError.value(userId, 'userId', 'User id must not be blank.'),
      );
    }

    final queued = _queued;
    if (queued != null && _queuedUserId == normalizedUserId) {
      return queued;
    }

    final completer = Completer<bool>();
    final run = completer.future;
    _queued = run;
    _queuedUserId = normalizedUserId;

    _pending = _pending.then((_) async {
      if (identical(_queued, run)) {
        _queued = null;
        _queuedUserId = null;
      }

      try {
        completer.complete(await _runSynchronization(normalizedUserId));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return run;
  }

  Future<bool> _runSynchronization(String userId) async {
    if (_currentUserId != userId) {
      await activateUser(userId);
    }

    // A run whose account was signed out or switched while it ran must not
    // report into the new account's state.
    final generation = _activationGeneration;
    bool isStale() =>
        generation != _activationGeneration || _currentUserId != userId;

    _status = SyncStatus.syncing;
    _lastError = null;
    _failureKind = null;
    notifyListeners();

    try {
      final SyncRunResult result;
      try {
        result = await _synchronize(userId);
      } catch (error) {
        if (isStale()) return false;
        rethrow;
      }

      if (isStale()) return false;

      _lastResult = result;
      _lastSuccessfulSync = result.completedAt;
      _pendingChanges = result.pendingAfterSync;
      _retryPending = result.hasRemainingPendingChanges;
      _status = SyncStatus.success;
      _lastError = null;
      notifyListeners();

      try {
        await _statusStore.saveLastSuccessfulSync(userId, result.completedAt);
      } catch (error) {
        // Sync succeeded. Failure to persist display-only status must not
        // turn a successful cloud synchronization into an error.
        _log('Could not save the last sync time', error);
      }

      return true;
    } on SyncHeldForRecovery catch (error) {
      // Not a failure: retrying would only be rejected again.
      _lastError = error;
      _retryPending = false;
      _status = SyncStatus.recoveryHold;

      return false;
    } on SyncNeedsCloudLibraryChoice catch (error) {
      // Not a failure: waiting for the person, not for a retry.
      _lastError = error;
      _retryPending = false;
      _status = SyncStatus.awaitingCloudChoice;

      return false;
    } on LocalAccountBindingConflict catch (error) {
      _lastError = error;
      _retryPending = false;
      _status = SyncStatus.accountConflict;

      return false;
    } catch (error) {
      _lastError = error;
      _retryPending = true;
      _status = SyncStatus.error;
      final kind = _failureKind = _classifyFailure(error);
      _log('Sync failed (${kind.name})', error);

      // Unsent changes stay in the outbox; show how many are waiting.
      final pending = await _readPendingCount(userId);
      if (pending != null && !isStale()) _pendingChanges = pending;

      return false;
    } finally {
      if (!isStale()) notifyListeners();
    }
  }

  static void _log(String message, Object error) {
    developer.log(
      '$message: ${error.runtimeType}',
      name: 'sonus.sync',
      level: 900,
      error: error,
    );
  }

  void resetForSignedOut() {
    _activationGeneration++;
    _failureKind = null;
    _currentUserId = null;
    _status = SyncStatus.idle;
    _lastSuccessfulSync = null;
    _pendingChanges = 0;
    _lastError = null;
    _lastResult = null;
    _retryPending = false;
    notifyListeners();
  }

  void clearError() {
    if (_lastError == null &&
        _status != SyncStatus.error &&
        _status != SyncStatus.accountConflict) {
      return;
    }

    _lastError = null;
    _failureKind = null;

    if (_status == SyncStatus.error || _status == SyncStatus.accountConflict) {
      _status = SyncStatus.idle;
    }

    notifyListeners();
  }

  void markRetryHandled() {
    if (!_retryPending) {
      return;
    }

    _retryPending = false;
    notifyListeners();
  }
}
