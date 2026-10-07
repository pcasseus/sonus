import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
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

        if (userId == 'user-1') {
          await firstGate.future;
        }

        calls.add('finish:$userId');

        return _result(userId: userId);
      },
    );

    addTearDown(controller.dispose);

    final first = controller.synchronize('user-1');
    final second = controller.synchronize('user-1');

    await Future<void>.delayed(Duration.zero);

    expect(calls, ['start:user-1']);

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
