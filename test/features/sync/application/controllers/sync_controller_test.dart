import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/models/sync_failure.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/data/services/sync_status_store.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_cancellation.dart';

void main() {
  test('starts idle', () {
    final controller = SyncController.forTesting(
      synchronize: (_) async => _result(),
    );

    addTearDown(controller.dispose);

    expect(controller.status, SyncStatus.idle);
    expect(controller.currentUserId, isNull);
    expect(controller.lastSuccessfulSync, isNull);
    expect(controller.pendingChanges, 0);
    expect(controller.lastError, isNull);
    expect(controller.lastResult, isNull);
    expect(controller.retryPending, isFalse);
    expect(controller.isSyncing, isFalse);
  });

  test('records successful sync state', () async {
    final completedAt = DateTime.utc(2026, 10, 6, 12, 5);

    final controller = SyncController.forTesting(
      synchronize: (userId) async {
        expect(userId, 'user-1');

        return _result(
          userId: userId,
          completedAt: completedAt,
          pendingAfterSync: 2,
        );
      },
    );

    addTearDown(controller.dispose);

    final succeeded = await controller.synchronize(' user-1 ');

    expect(succeeded, isTrue);
    expect(controller.status, SyncStatus.success);
    expect(controller.currentUserId, 'user-1');
    expect(controller.lastSuccessfulSync, completedAt);
    expect(controller.pendingChanges, 2);
    expect(controller.lastResult, isNotNull);
    expect(controller.lastError, isNull);
    expect(controller.retryPending, isTrue);
  });

  test('records normal failure and schedules quiet retry', () async {
    final error = StateError('network unavailable');

    final controller = SyncController.forTesting(
      synchronize: (_) async => throw error,
    );

    addTearDown(controller.dispose);

    final succeeded = await controller.synchronize('user-1');

    expect(succeeded, isFalse);
    expect(controller.status, SyncStatus.error);
    expect(controller.lastError, same(error));
    expect(controller.retryPending, isTrue);
    expect(controller.hasError, isTrue);
    expect(controller.hasAccountConflict, isFalse);
  });

  test('records account conflict without scheduling retry', () async {
    const error = LocalAccountBindingConflict(
      boundUserId: 'user-1',
      requestedUserId: 'user-2',
    );

    final controller = SyncController.forTesting(
      synchronize: (_) async => throw error,
    );

    addTearDown(controller.dispose);

    final succeeded = await controller.synchronize('user-2');

    expect(succeeded, isFalse);
    expect(controller.status, SyncStatus.accountConflict);
    expect(controller.lastError, same(error));
    expect(controller.retryPending, isFalse);
    expect(controller.hasAccountConflict, isTrue);
  });

  test('serializes overlapping sync requests', () async {
    final calls = <String>[];
    final firstGate = Completer<void>();

    final controller = SyncController.forTesting(
      synchronize: (userId) async {
        calls.add('start:$userId');

        if (userId == 'user-1' && !firstGate.isCompleted) {
          await firstGate.future;
        }

        calls.add('finish:$userId');

        return _result(userId: userId);
      },
    );

    addTearDown(controller.dispose);

    final first = controller.synchronize('user-1');
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start:user-1']);

    // Requested while a run is in progress: one more run follows it, so
    // changes made during the first run still reach the cloud.
    final second = controller.synchronize('user-1');

    firstGate.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);

    expect(calls, [
      'start:user-1',
      'finish:user-1',
      'start:user-1',
      'finish:user-1',
    ]);
  });

  test('many Sync Now taps run once more, not once per tap', () async {
    var runs = 0;
    final gate = Completer<void>();

    final controller = SyncController.forTesting(
      synchronize: (userId) async {
        runs++;
        if (runs == 1) await gate.future;
        return _result(userId: userId);
      },
    );

    addTearDown(controller.dispose);

    final first = controller.synchronize('user-1');
    await Future<void>.delayed(Duration.zero);

    final taps = [for (var i = 0; i < 5; i++) controller.synchronize('user-1')];
    gate.complete();

    expect(await first, isTrue);
    expect(await Future.wait(taps), everyElement(isTrue));
    expect(runs, 2);
    expect(controller.isSyncing, isFalse);
  });

  group('resilience (SN-45)', () {
    test('a run that ends after sign-out changes nothing', () async {
      final gate = Completer<SyncRunResult>();
      final saved = <String>[];
      final controller = SyncController.forTesting(
        synchronize: (_) => gate.future,
        statusStore: SyncStatusStore.forTesting(
          getString: (_) async => null,
          setString: (_, value) async => saved.add(value),
        ),
      );
      addTearDown(controller.dispose);

      final run = controller.synchronize('user-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isSyncing, isTrue);

      controller.resetForSignedOut();
      gate.complete(_result());

      expect(await run, isFalse);
      expect(controller.status, SyncStatus.idle);
      expect(controller.lastSuccessfulSync, isNull);
      expect(saved, isEmpty);
    });

    test(
      'a run for a previous account does not report into the new one',
      () async {
        final gate = Completer<SyncRunResult>();
        final controller = SyncController.forTesting(
          synchronize: (userId) =>
              userId == 'user-1' ? gate.future : Future.value(_result()),
        );
        addTearDown(controller.dispose);

        final old = controller.synchronize('user-1');
        await Future<void>.delayed(Duration.zero);
        await controller.activateUser('user-2');

        gate.completeError(TimeoutException('late'));
        expect(await old, isFalse);

        expect(controller.currentUserId, 'user-2');
        expect(controller.status, SyncStatus.idle);
        expect(controller.failureKind, isNull);
      },
    );

    test('a failure keeps the previous Last synced time', () async {
      var fail = false;
      final controller = SyncController.forTesting(
        synchronize: (_) async {
          if (fail) throw TimeoutException('stalled');
          return _result(completedAt: DateTime.utc(2026, 10, 1));
        },
      );
      addTearDown(controller.dispose);

      await controller.synchronize('user-1');
      fail = true;
      await controller.synchronize('user-1');

      expect(controller.status, SyncStatus.error);
      expect(controller.failureKind, SyncFailureKind.timeout);
      expect(controller.lastSuccessfulSync, DateTime.utc(2026, 10, 1));
    });

    test('success shows before the last-sync time is saved', () async {
      final saving = Completer<void>();
      final controller = SyncController.forTesting(
        synchronize: (_) async => _result(),
        statusStore: SyncStatusStore.forTesting(
          getString: (_) async => null,
          setString: (_, _) => saving.future,
        ),
      );
      addTearDown(controller.dispose);

      final run = controller.synchronize('user-1');
      await pumpEventQueue();

      expect(controller.status, SyncStatus.success);
      expect(controller.isSyncing, isFalse);

      saving.complete();
      expect(await run, isTrue);
    });

    test('the injected classifier names the failure', () async {
      final controller = SyncController.forTesting(
        synchronize: (_) async => throw StateError('rejected'),
        classifyFailure: (_) => SyncFailureKind.signIn,
      );
      addTearDown(controller.dispose);

      await controller.synchronize('user-1');

      expect(controller.failureKind, SyncFailureKind.signIn);
      expect(controller.isSyncing, isFalse);
    });

    test(
      'pending changes are counted before any sync and after failures',
      () async {
        var pending = 3;
        final controller = SyncController.forTesting(
          synchronize: (_) async => throw TimeoutException('stalled'),
          countPending: (_) async => pending,
        );
        addTearDown(controller.dispose);

        await controller.activateUser('user-1');
        expect(controller.pendingChanges, 3);

        pending = 4;
        await controller.synchronize('user-1');
        expect(controller.pendingChanges, 4);
        expect(controller.lastSuccessfulSync, isNull);
      },
    );
  });

  test('an unreadable network state does not escape a trigger', () async {
    final controller = SyncController.forTesting(
      synchronize: (_) async => _result(),
    );
    addTearDown(controller.dispose);
    final coordinator = AutomaticSyncCoordinator(
      syncController: controller,
      networkPolicy: SyncNetworkPolicyService.forTesting(
        checkConnectivity: () async => throw StateError('no platform'),
        getBool: (_) async => null,
        setBool: (_, _) async {},
        remove: (_) async {},
      ),
    );
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');
    await coordinator.trigger();

    expect(controller.isSyncing, isFalse);
  });

  test('rejects blank user id before queueing sync', () async {
    var called = false;

    final controller = SyncController.forTesting(
      synchronize: (_) async {
        called = true;
        return _result();
      },
    );

    addTearDown(controller.dispose);

    await expectLater(() => controller.synchronize('   '), throwsArgumentError);

    expect(called, isFalse);
    expect(controller.status, SyncStatus.idle);
  });

  test('resetForSignedOut clears account-specific sync state', () async {
    final controller = SyncController.forTesting(
      synchronize: (userId) async =>
          _result(userId: userId, pendingAfterSync: 3),
    );

    addTearDown(controller.dispose);

    await controller.synchronize('user-1');

    controller.resetForSignedOut();

    expect(controller.status, SyncStatus.idle);
    expect(controller.currentUserId, isNull);
    expect(controller.pendingChanges, 0);
    expect(controller.lastError, isNull);
    expect(controller.lastResult, isNull);
    expect(controller.retryPending, isFalse);
  });

  test('clearError returns error state to idle', () async {
    final controller = SyncController.forTesting(
      synchronize: (_) async => throw StateError('failed'),
    );

    addTearDown(controller.dispose);

    await controller.synchronize('user-1');

    expect(controller.status, SyncStatus.error);

    controller.clearError();

    expect(controller.status, SyncStatus.idle);
    expect(controller.lastError, isNull);
  });

  test('markRetryHandled clears retry flag', () async {
    final controller = SyncController.forTesting(
      synchronize: (_) async => throw StateError('failed'),
    );

    addTearDown(controller.dispose);

    await controller.synchronize('user-1');

    expect(controller.retryPending, isTrue);

    controller.markRetryHandled();

    expect(controller.retryPending, isFalse);
  });
  group('SN-50 reconciliation: bounded runs, one at a time', () {
    const limit = Duration(milliseconds: 40);
    Future<void> pastTheLimit() =>
        Future<void>.delayed(limit + const Duration(milliseconds: 40));

    test('a run that never ends is reported as timed out, with the changes '
        'kept for a retry', () async {
      final hung = Completer<SyncRunResult>();
      final controller = SyncController.forTesting(
        synchronize: (_) => hung.future,
        countPending: (_) async => 3,
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      final run = controller.synchronize('user-1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isSyncing, isTrue);

      expect(await run, isFalse);
      expect(controller.isSyncing, isFalse);
      expect(controller.status, SyncStatus.error);
      expect(controller.failureKind, SyncFailureKind.timeout);
      expect(controller.failureCode, 'SyncRunTimedOut');
      expect(controller.lastError, isA<SyncRunTimedOut>());
      expect(controller.retryPending, isTrue);
      expect(controller.pendingChanges, 3, reason: 'nothing is dropped');
      expect(controller.lastSuccessfulSync, isNull);
    });

    test('the next run never starts while a timed-out run is still going; '
        'it starts once that run has ended', () async {
      final hung = Completer<SyncRunResult>();
      final starts = <int>[];
      final controller = SyncController.forTesting(
        synchronize: (_) {
          starts.add(starts.length + 1);
          return starts.length == 1 ? hung.future : Future.value(_result());
        },
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isFalse);

      // Requested behind the run that has not ended: the caller gets an
      // answer within the limit, and no second run writes alongside.
      final retry = controller.synchronize('user-1');
      expect(await retry, isFalse);
      await pastTheLimit();
      expect(starts, [1]);

      hung.completeError(StateError('ended late'));
      await pumpEventQueue();

      expect(starts, [1, 2], reason: 'the queued run ran, nothing dropped');
      expect(controller.status, SyncStatus.success);
      expect(controller.failureCode, isNull);
    });

    test('a run that ends after its time limit is never reported as a '
        'success', () async {
      final lateRun = Completer<SyncRunResult>();
      final saved = <String>[];
      final controller = SyncController.forTesting(
        synchronize: (_) => lateRun.future,
        statusStore: SyncStatusStore.forTesting(
          getString: (_) async => null,
          setString: (_, value) async => saved.add(value),
        ),
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isFalse);
      lateRun.complete(_result());
      await pumpEventQueue();

      expect(controller.status, SyncStatus.error);
      expect(controller.failureKind, SyncFailureKind.timeout);
      expect(controller.lastSuccessfulSync, isNull);
      expect(controller.lastResult, isNull);
      expect(saved, isEmpty);
    });

    test('a run within the limit is unaffected', () async {
      final controller = SyncController.forTesting(
        synchronize: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return _result();
        },
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isTrue);
      await pastTheLimit();
      expect(controller.status, SyncStatus.success);
    });

    test('signing out during a run that never ends, then back in: the new '
        'sync waits for it and then runs', () async {
      final hung = Completer<SyncRunResult>();
      final starts = <String>[];
      final controller = SyncController.forTesting(
        synchronize: (userId) {
          starts.add(userId);
          return starts.length == 1 ? hung.future : Future.value(_result());
        },
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      final first = controller.synchronize('user-1');
      await Future<void>.delayed(Duration.zero);
      controller.resetForSignedOut();
      expect(controller.status, SyncStatus.idle);

      await controller.activateUser('user-1');
      expect(await controller.synchronize('user-1'), isFalse);
      expect(await first, isFalse);
      expect(starts, ['user-1'], reason: 'never two runs at once');
      expect(
        controller.status,
        SyncStatus.idle,
        reason: 'the old run is stale',
      );

      hung.complete(_result());
      await pumpEventQueue();

      expect(starts, ['user-1', 'user-1']);
      expect(controller.currentUserId, 'user-1');
      expect(controller.status, SyncStatus.success);
    });

    test(
      'a run queued before sign-out never signs the account back in',
      () async {
        final gate = Completer<void>();
        final starts = <String>[];
        final controller = SyncController.forTesting(
          synchronize: (userId) async {
            starts.add(userId);
            if (starts.length == 1) await gate.future;
            return _result(userId: userId);
          },
        );
        addTearDown(controller.dispose);

        final first = controller.synchronize('user-1');
        await Future<void>.delayed(Duration.zero);
        final queued = controller.synchronize('user-1');

        controller.resetForSignedOut();
        gate.complete();

        expect(await first, isFalse);
        expect(await queued, isFalse);
        expect(starts, ['user-1']);
        expect(controller.currentUserId, isNull);
        expect(controller.status, SyncStatus.idle);
      },
    );

    test('rapid account changes: a run queued for the previous account is '
        'skipped, and the new account syncs once', () async {
      final gate = Completer<void>();
      final starts = <String>[];
      final controller = SyncController.forTesting(
        synchronize: (userId) async {
          starts.add(userId);
          if (starts.length == 1) await gate.future;
          return _result(userId: userId);
        },
      );
      addTearDown(controller.dispose);

      final first = controller.synchronize('user-1');
      await Future<void>.delayed(Duration.zero);
      final staleQueued = controller.synchronize('user-1');
      await controller.activateUser('user-2');
      final second = controller.synchronize('user-2');
      gate.complete();

      expect(await first, isFalse);
      expect(await staleQueued, isFalse);
      expect(await second, isTrue);
      expect(starts, ['user-1', 'user-2']);
      expect(controller.currentUserId, 'user-2');
      expect(controller.status, SyncStatus.success);
    });

    test('the failure code is cleared with the failure', () async {
      final controller = SyncController.forTesting(
        synchronize: (_) => Future.error(StateError('offline')),
      );
      addTearDown(controller.dispose);

      await controller.synchronize('user-1');
      expect(controller.failureCode, isNotNull);
      controller.clearError();
      expect(controller.failureCode, isNull);

      await controller.synchronize('user-1');
      expect(controller.failureCode, isNotNull);
      await controller.activateUser('user-2');
      expect(controller.failureCode, isNull);

      await controller.synchronize('user-2');
      expect(controller.failureCode, isNotNull);
      controller.resetForSignedOut();
      expect(controller.failureCode, isNull);
    });

    test(
      'disposing while a run is going leaves no time limit behind',
      () async {
        final hung = Completer<SyncRunResult>();
        final controller = SyncController.forTesting(
          synchronize: (_) => hung.future,
          runTimeout: limit,
        );

        unawaited(controller.synchronize('user-1'));
        await Future<void>.delayed(Duration.zero);
        controller.dispose();

        await pastTheLimit();
        hung.complete(_result());
        await pumpEventQueue();
      },
    );
  });
  group('SN-50 #23: cancellation stops a run at its next safe point', () {
    const limit = Duration(milliseconds: 60);

    late List<String> writes;
    late int active;
    late int maxActive;

    setUp(() {
      writes = [];
      active = 0;
      maxActive = 0;
    });

    /// A service run doing units of work until it is cancelled: each unit
    /// is one write, recorded with its account, after a safe point.
    /// [hold] can keep one unit open, as a slow network response would.
    Future<SyncRunResult> endless(
      String userId, {
      Future<void> Function(int unit)? hold,
    }) async {
      active++;
      if (active > maxActive) maxActive = active;
      try {
        for (var unit = 0; ; unit++) {
          SyncCancellation.checkpoint();
          await (hold?.call(unit) ??
              Future<void>.delayed(const Duration(milliseconds: 2)));
          writes.add('$userId:$unit');
        }
      } finally {
        active--;
      }
    }

    Future<SyncRunResult> quick(String userId) async {
      active++;
      if (active > maxActive) maxActive = active;
      try {
        writes.add('$userId:done');
        return _result(userId: userId);
      } finally {
        active--;
      }
    }

    test('a timed-out run stops at its next safe point, so a retry starts '
        'at once and never alongside it', () async {
      var calls = 0;
      final controller = SyncController.forTesting(
        synchronize: (userId) => ++calls == 1 ? endless(userId) : quick(userId),
        runTimeout: limit,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isFalse);
      expect(controller.failureKind, SyncFailureKind.timeout);

      expect(await controller.synchronize('user-1'), isTrue);
      expect(controller.status, SyncStatus.success);
      expect(maxActive, 1, reason: 'never two runs at once');
      expect(writes.last, 'user-1:done');
      expect(
        writes.where((w) => w != 'user-1:done'),
        everyElement(startsWith('user-1:')),
      );
    });

    test('signing out stops the run; nothing more is written for that '
        'account', () async {
      final controller = SyncController.forTesting(
        synchronize: (userId) => endless(userId),
      );
      addTearDown(controller.dispose);

      final run = controller.synchronize('user-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.resetForSignedOut();
      final writtenAtSignOut = writes.length;

      expect(await run, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        writes.length,
        lessThanOrEqualTo(writtenAtSignOut + 1),
        reason: 'at most the unit already in flight finishes',
      );
      final settled = writes.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(writes.length, settled);
      expect(active, 0);
      expect(controller.status, SyncStatus.idle);
    });

    test('switching account stops the old run before the new account '
        'syncs; nothing is written for the old account afterwards', () async {
      var calls = 0;
      final controller = SyncController.forTesting(
        synchronize: (userId) => ++calls == 1 ? endless(userId) : quick(userId),
      );
      addTearDown(controller.dispose);

      final old = controller.synchronize('user-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.activateUser('user-2');
      final next = controller.synchronize('user-2');

      expect(await old, isFalse);
      expect(await next, isTrue);

      final switchedAt = writes.indexOf('user-2:done');
      expect(writes.sublist(switchedAt + 1), isEmpty);
      expect(maxActive, 1);
      expect(controller.currentUserId, 'user-2');
      expect(controller.status, SyncStatus.success);
    });

    test(
      'a unit whose response arrives after cancellation finishes whole, '
      'and nothing follows it; the run is never reported as a success',
      () async {
        final response = Completer<void>();
        final inFlight = Completer<void>();
        final controller = SyncController.forTesting(
          synchronize: (userId) => endless(
            userId,
            hold: (unit) async {
              if (unit == 1) {
                inFlight.complete();
                await response.future;
              }
            },
          ),
        );
        addTearDown(controller.dispose);

        final run = controller.synchronize('user-1');
        await inFlight.future;
        controller.resetForSignedOut();
        response.complete();

        expect(await run, isFalse);
        await pumpEventQueue();

        expect(writes, ['user-1:0', 'user-1:1']);
        expect(active, 0);
        expect(controller.status, isNot(SyncStatus.success));
        expect(controller.lastSuccessfulSync, isNull);
      },
    );

    test('disposing stops the run at its next safe point', () async {
      final controller = SyncController.forTesting(
        synchronize: (userId) => endless(userId),
      );

      unawaited(controller.synchronize('user-1'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final settled = writes.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(writes.length, settled);
      expect(active, 0);
    });

    test('outside a sync run a safe point never throws', () {
      expect(SyncCancellation.checkpoint, returnsNormally);
      expect(SyncCancellation.current, isNull);
    });
  });
  group('SN-50: sync paused for a permanent failure', () {
    late Map<String, String> stored;

    SyncStatusStore store() => SyncStatusStore.forTesting(
      getString: (key) async => stored[key],
      setString: (key, value) async => stored[key] = value,
    );

    setUp(() => stored = {});

    test('pauses, keeps the pending changes and the last sync time, and '
        'schedules no automatic retry', () async {
      var calls = 0;
      final controller = SyncController.forTesting(
        synchronize: (userId) async {
          if (++calls == 1) return _result(userId: userId);
          throw CloudContractMismatch('no server revision');
        },
        statusStore: store(),
        countPending: (_) async => 4,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isTrue);
      final lastSynced = controller.lastSuccessfulSync;

      expect(await controller.synchronize('user-1'), isFalse);

      expect(controller.status, SyncStatus.paused);
      expect(controller.isPaused, isTrue);
      expect(controller.failureKind, SyncFailureKind.cloudNotReady);
      expect(controller.failureCode, 'CloudContractMismatch');
      expect(controller.retryPending, isFalse);
      expect(controller.pendingChanges, 4);
      expect(controller.lastSuccessfulSync, lastSynced);
      expect(controller.pausedSince, isNotNull);
    });

    test(
      'a temporary failure never pauses, however often it happens',
      () async {
        final controller = SyncController.forTesting(
          synchronize: (_) => Future.error(TimeoutException('slow')),
          statusStore: store(),
        );
        addTearDown(controller.dispose);

        for (var attempt = 0; attempt < 5; attempt++) {
          await controller.synchronize('user-1');
        }

        expect(controller.status, SyncStatus.error);
        expect(controller.isPaused, isFalse);
        expect(controller.retryPending, isTrue);
        expect(stored.keys.where((k) => k.startsWith('sync.paused.')), isEmpty);
      },
    );

    test('the pause belongs to its account and survives sign-out and '
        'sign-in', () async {
      final controller = SyncController.forTesting(
        synchronize: (userId) => userId == 'user-1'
            ? Future.error(CloudContractMismatch('no server revision'))
            : Future.value(_result(userId: userId)),
        statusStore: store(),
      );
      addTearDown(controller.dispose);

      await controller.synchronize('user-1');
      final since = controller.pausedSince;
      expect(controller.isPaused, isTrue);

      controller.resetForSignedOut();
      expect(controller.isPaused, isFalse);

      await controller.activateUser('user-2');
      expect(controller.isPaused, isFalse);
      expect(await controller.synchronize('user-2'), isTrue);

      controller.resetForSignedOut();
      await controller.activateUser('user-1');
      expect(controller.isPaused, isTrue);
      expect(controller.failureCode, 'CloudContractMismatch');
      expect(controller.pausedSince, since);
    });

    test('a retry that succeeds clears the pause for good', () async {
      var cloudReady = false;
      final controller = SyncController.forTesting(
        synchronize: (userId) => cloudReady
            ? Future.value(_result(userId: userId))
            : Future.error(CloudContractMismatch('no server revision')),
        statusStore: store(),
      );
      addTearDown(controller.dispose);

      await controller.synchronize('user-1');
      expect(controller.isPaused, isTrue);

      cloudReady = true;
      expect(await controller.synchronize('user-1'), isTrue);
      expect(controller.status, SyncStatus.success);
      expect(controller.pausedSince, isNull);

      controller.resetForSignedOut();
      await controller.activateUser('user-1');
      expect(controller.isPaused, isFalse);
    });

    test(
      'while paused, automatic triggers do nothing; Retry runs once',
      () async {
        var calls = 0;
        final controller = SyncController.forTesting(
          synchronize: (_) {
            calls++;
            return Future.error(CloudContractMismatch('no server revision'));
          },
          statusStore: store(),
        );
        addTearDown(controller.dispose);
        final coordinator = AutomaticSyncCoordinator(
          syncController: controller,
          networkPolicy: SyncNetworkPolicyService.forTesting(
            checkConnectivity: () async => [ConnectivityResult.wifi],
            getBool: (_) async => null,
            setBool: (_, _) async {},
            remove: (_) async {},
          ),
        );
        coordinator.updateUserId('user-1');
        await pumpEventQueue();

        await coordinator.trigger();
        expect(calls, 1);
        expect(controller.isPaused, isTrue);

        await coordinator.trigger();
        await coordinator.trigger();
        expect(calls, 1, reason: 'no automatic retries while paused');

        await coordinator.trigger(retry: true);
        expect(calls, 2);
        expect(controller.isPaused, isTrue);
      },
    );
  });
}

SyncRunResult _result({
  String userId = 'user-1',
  DateTime? completedAt,
  int pendingAfterSync = 0,
}) {
  final startedAt = DateTime.utc(2026, 10, 6, 12);

  return SyncRunResult(
    userId: userId,
    startedAt: startedAt,
    completedAt: completedAt ?? DateTime.utc(2026, 10, 6, 12, 0, 5),
    claimedUnownedCount: 0,
    pendingBeforePush: 0,
    pulledRecordCount: 0,
    pendingAfterSync: pendingAfterSync,
  );
}
