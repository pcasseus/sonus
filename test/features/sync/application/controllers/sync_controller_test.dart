import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/models/sync_failure.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/data/services/sync_status_store.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

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
