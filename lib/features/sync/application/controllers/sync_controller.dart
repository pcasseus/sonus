import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../../data/services/sync_status_store.dart';
import '../services/sync_service.dart';

enum SyncStatus { idle, syncing, success, error, accountConflict }

class SyncController extends ChangeNotifier {
  SyncController({required SyncService service, SyncStatusStore? statusStore})
    : this._(
        synchronize: service.synchronize,
        statusStore: statusStore ?? SyncStatusStore(),
      );

  @visibleForTesting
  SyncController.forTesting({
    required Future<SyncRunResult> Function(String userId) synchronize,
    SyncStatusStore? statusStore,
  }) : this._(
         synchronize: synchronize,
         statusStore:
             statusStore ??
             SyncStatusStore.forTesting(
               getString: (_) async => null,
               setString: (_, _) async {},
             ),
       );

  SyncController._({required this._synchronize, required this._statusStore});

  final Future<SyncRunResult> Function(String userId) _synchronize;
  final SyncStatusStore _statusStore;

  Future<void> _pending = Future<void>.value();

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

  bool get isSyncing => _status == SyncStatus.syncing;

  bool get hasError =>
      _status == SyncStatus.error || _status == SyncStatus.accountConflict;

  bool get hasAccountConflict => _status == SyncStatus.accountConflict;

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
    notifyListeners();

    DateTime? restored;

    try {
      restored = await _statusStore.getLastSuccessfulSync(normalizedUserId);
    } catch (_) {
      return;
    }

    if (generation != _activationGeneration ||
        _currentUserId != normalizedUserId) {
      return;
    }

    _lastSuccessfulSync = restored;
    notifyListeners();
  }

  Future<bool> synchronize(String userId) {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      return Future<bool>.error(
        ArgumentError.value(userId, 'userId', 'User id must not be blank.'),
      );
    }

    final completer = Completer<bool>();

    _pending = _pending.then((_) async {
      try {
        completer.complete(await _runSynchronization(normalizedUserId));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<bool> _runSynchronization(String userId) async {
    if (_currentUserId != userId) {
      await activateUser(userId);
    }

    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final result = await _synchronize(userId);

      _lastResult = result;
      _lastSuccessfulSync = result.completedAt;
      _pendingChanges = result.pendingAfterSync;
      _retryPending = result.hasRemainingPendingChanges;
      _status = SyncStatus.success;
      _lastError = null;

      try {
        await _statusStore.saveLastSuccessfulSync(userId, result.completedAt);
      } catch (_) {
        // Sync succeeded. Failure to persist display-only status must not
        // turn a successful cloud synchronization into an error.
      }

      return true;
    } on LocalAccountBindingConflict catch (error) {
      _lastError = error;
      _retryPending = false;
      _status = SyncStatus.accountConflict;

      return false;
    } catch (error) {
      _lastError = error;
      _retryPending = true;
      _status = SyncStatus.error;

      return false;
    } finally {
      notifyListeners();
    }
  }

  void resetForSignedOut() {
    _activationGeneration++;
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
