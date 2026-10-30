import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../../data/services/sync_status_store.dart';
import '../models/sync_failure.dart';
import '../services/cloud_library_first_link_guard.dart';
import '../services/sync_cancellation.dart';
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
    SyncFailureDescriber describeFailure = describeSyncFailure,
    Future<void> Function(String userId)? grantCloudLibrary,
    Duration runTimeout = defaultRunTimeout,
  }) : this._(
         synchronize: service.synchronize,
         statusStore: statusStore ?? SyncStatusStore(),
         countPending: service.pendingCount,
         classifyFailure: classifyFailure,
         describeFailure: describeFailure,
         grantCloudLibrary: grantCloudLibrary,
         runTimeout: runTimeout,
       );

  @visibleForTesting
  SyncController.forTesting({
    required Future<SyncRunResult> Function(String userId) synchronize,
    SyncStatusStore? statusStore,
    Future<int> Function(String userId)? countPending,
    SyncFailureClassifier classifyFailure = classifySyncFailure,
    SyncFailureDescriber describeFailure = describeSyncFailure,
    Future<void> Function(String userId)? grantCloudLibrary,
    Duration runTimeout = defaultRunTimeout,
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
         describeFailure: describeFailure,
         grantCloudLibrary: grantCloudLibrary,
         runTimeout: runTimeout,
       );

  SyncController._({
    required this._synchronize,
    required this._statusStore,
    required this._countPending,
    required this._classifyFailure,
    required this._describeFailure,
    required this._grantCloudLibrary,
    required this._runTimeout,
  });

  /// How long a run, or a request waiting behind one, is waited for before
  /// it is reported as timed out. Generous: a first sync can be long.
  static const Duration defaultRunTimeout = Duration(minutes: 10);

  final Future<SyncRunResult> Function(String userId) _synchronize;
  final SyncStatusStore _statusStore;

  /// Reads the local outbox, so pending work is shown before any run.
  final Future<int> Function(String userId)? _countPending;
  final SyncFailureClassifier _classifyFailure;
  final SyncFailureDescriber _describeFailure;
  final Future<void> Function(String userId)? _grantCloudLibrary;
  final Duration _runTimeout;

  /// Ends when the last queued service run has really ended, including a
  /// run that went past [_runTimeout] and was no longer waited for. Runs
  /// start one after another on it, so two runs never write at once.
  Future<void> _pending = Future<void>.value();

  /// Changes when the person signs out or switches account. A run queued
  /// for an account that is no longer signed in is never started.
  int _sessionEpoch = 0;

  final Set<Timer> _timers = {};
  bool _disposed = false;

  /// The service run in progress, if any. Cancelled on timeout, sign-out,
  /// a switch to another account and disposal; it then stops at its next
  /// safe point, so the next run can start without overlapping it.
  SyncCancellation? _activeRun;

  /// A run waiting behind the current one. Further requests join it, so a
  /// burst of triggers or taps runs at most once more.
  Future<bool>? _queued;
  String? _queuedUserId;

  SyncFailureKind? _failureKind;
  String? _failureCode;

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

  /// A short code for the last failure (see [SyncFailureDescriber]); null
  /// unless [status] is error.
  String? get failureCode => _failureCode;

  bool get isSyncing => _status == SyncStatus.syncing;

  bool get hasError =>
      _status == SyncStatus.error || _status == SyncStatus.accountConflict;

  bool get hasAccountConflict => _status == SyncStatus.accountConflict;

  bool get isRecoveryHeld => _status == SyncStatus.recoveryHold;

  bool get isAwaitingCloudChoice => _status == SyncStatus.awaitingCloudChoice;

  /// While [isAwaitingCloudChoice]: true when the account already has a
  /// cloud library to bring here; false when this device's library would
  /// be the first one sent to the account.
  bool get cloudChoiceHasCloudLibrary => switch (_lastError) {
    SyncNeedsCloudLibraryChoice(:final cloudHasLibrary) => cloudHasLibrary,
    _ => false,
  };

  /// The person chose to start syncing this device with the account
  /// (bringing its cloud library here, or sending this library to it):
  /// records the choice and syncs.
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

  Future<void> activateUser(String userId) =>
      _activate(userId, newSession: true);

  Future<void> _activate(String userId, {required bool newSession}) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (_currentUserId == normalizedUserId) {
      return;
    }

    if (newSession) {
      _sessionEpoch++;
      _activeRun?.cancel('account switched');
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
    _failureCode = null;
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
    final epoch = _sessionEpoch;

    // Behind a run that never ends, the caller still gets an answer within
    // the time limit. The run keeps its place and starts when its turn
    // comes; a later request queues a new run rather than joining this one.
    final waitLimit = _startTimer(() {
      if (completer.isCompleted) return;
      if (identical(_queued, run)) {
        _queued = null;
        _queuedUserId = null;
      }
      completer.complete(false);
    });

    _pending = _pending.then((_) async {
      _cancelTimer(waitLimit);
      if (identical(_queued, run)) {
        _queued = null;
        _queuedUserId = null;
      }

      var ended = Future<void>.value();
      try {
        final result = await _runSynchronization(
          normalizedUserId,
          epoch,
          onServiceStarted: (serviceEnded) => ended = serviceEnded,
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }

      // The next run starts only once this one has really ended.
      await ended;
    });

    return run;
  }

  Future<bool> _runSynchronization(
    String userId,
    int epoch, {
    required void Function(Future<void> serviceEnded) onServiceStarted,
  }) async {
    if (_disposed) return false;

    if (epoch != _sessionEpoch && _currentUserId != userId) {
      // Requested for an account that has since been signed out or
      // switched away from: never sign it back in behind the person.
      _log(
        'A queued sync for an account that is no longer active was skipped',
        StateError('stale session'),
      );
      return false;
    }

    if (_currentUserId != userId) {
      await _activate(userId, newSession: false);
    }

    // A run whose account was signed out or switched while it ran, or whose
    // controller was disposed, must not report into any state.
    final generation = _activationGeneration;
    bool isStale() =>
        _disposed ||
        generation != _activationGeneration ||
        _currentUserId != userId;

    _status = SyncStatus.syncing;
    _lastError = null;
    _failureKind = null;
    _failureCode = null;
    notifyListeners();

    try {
      final SyncRunResult result;
      try {
        result = await _bounded(userId, onServiceStarted);
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
      final code = _failureCode = _describeFailure(error);
      _log('Sync failed (${kind.name})', error);
      debugPrint(syncFailureLogLine(kind, code, error));

      // Unsent changes stay in the outbox; show how many are waiting.
      final pending = await _readPendingCount(userId);
      if (pending != null && !isStale()) _pendingChanges = pending;

      return false;
    } finally {
      if (!isStale()) notifyListeners();
    }
  }

  /// The service run, waited for at most [_runTimeout]. A run past the
  /// limit is cancelled: it stops at its next safe point (between whole
  /// units of work, SN-50 #23) and its result is not used, so it is never
  /// reported as a success. The queue holds the next run until it has
  /// really ended ([onServiceStarted]), so two runs never write at once.
  Future<SyncRunResult> _bounded(
    String userId,
    void Function(Future<void> serviceEnded) onServiceStarted,
  ) {
    final cancellation = _activeRun = SyncCancellation(userId);
    final service = cancellation.run(
      () => Future<SyncRunResult>.sync(() => _synchronize(userId)),
    );
    final ended = service.then<void>((_) {}, onError: (Object _) {});
    unawaited(
      ended.whenComplete(() {
        if (identical(_activeRun, cancellation)) _activeRun = null;
      }),
    );
    onServiceStarted(ended);

    final outcome = Completer<SyncRunResult>();
    final limit = _startTimer(() {
      if (!outcome.isCompleted) {
        // Stop the run at its next safe point; its result is not used.
        cancellation.cancel('timed out');
        outcome.completeError(SyncRunTimedOut(_runTimeout));
      }
    });

    service.then(
      (result) {
        _cancelTimer(limit);
        if (outcome.isCompleted) {
          developer.log(
            'A sync run that went past its time limit has ended; its result '
            'is not used.',
            name: 'sonus.sync',
            level: 900,
          );
          return;
        }
        outcome.complete(result);
      },
      onError: (Object error, StackTrace stackTrace) {
        _cancelTimer(limit);
        if (outcome.isCompleted) {
          _log('A sync run that went past its time limit failed', error);
          return;
        }
        outcome.completeError(error, stackTrace);
      },
    );

    return outcome.future;
  }

  Timer _startTimer(void Function() onTimeout) {
    late final Timer timer;
    timer = Timer(_runTimeout, () {
      _timers.remove(timer);
      if (!_disposed) onTimeout();
    });
    _timers.add(timer);
    return timer;
  }

  void _cancelTimer(Timer timer) {
    timer.cancel();
    _timers.remove(timer);
  }

  @override
  void dispose() {
    _disposed = true;
    _activeRun?.cancel('disposed');
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  /// One line for the device log, which release builds keep (unlike
  /// developer.log): kind, code, and, for the app's own StateError or
  /// ArgumentError, its fixed developer message. Server and SDK messages
  /// are never included, since they can carry names or record contents.
  @visibleForTesting
  static String syncFailureLogLine(
    SyncFailureKind kind,
    String code,
    Object error,
  ) {
    final detail = switch (error) {
      StateError(:final message) => ': $message',
      ArgumentError(:final message?) => ': $message',
      _ => '',
    };
    final line = 'sonus.sync: sync failed (${kind.name}, $code)$detail';
    return line.length > 300 ? '${line.substring(0, 300)}…' : line;
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
    _sessionEpoch++;
    _activeRun?.cancel('signed out');
    _activationGeneration++;
    _failureKind = null;
    _failureCode = null;
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
    _failureCode = null;

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

/// A sync run went on past the controller's time limit. The run itself is
/// not stopped: the next run waits until it has ended, and its result is
/// not used. Unsent changes stay in the outbox.
class SyncRunTimedOut extends TimeoutException {
  SyncRunTimedOut(Duration limit)
    : super('The sync run did not finish in time.', limit);
}
