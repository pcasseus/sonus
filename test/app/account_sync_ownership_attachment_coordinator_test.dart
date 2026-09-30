import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/app/account_sync_ownership_attachment_coordinator.dart';

void main() {
  test('attaches normalized account id', () async {
    final calls = <String>[];

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (userId) async {
        calls.add(userId);
      },
    );

    coordinator.updateUserId(' user-1 ');

    await coordinator.settled;

    expect(calls, ['user-1']);
    expect(coordinator.currentUserId, 'user-1');
    expect(coordinator.attachedUserId, 'user-1');
    expect(coordinator.failedUserId, isNull);
    expect(coordinator.lastError, isNull);
  });

  test('repeated notification for attached user is idempotent', () async {
    var calls = 0;

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (_) async {
        calls++;
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(calls, 1);
  });

  test('sign-out resets attachment so same user can attach again', () async {
    var calls = 0;

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (_) async {
        calls++;
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    coordinator.updateUserId(null);
    await coordinator.settled;

    expect(coordinator.attachedUserId, isNull);

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(calls, 2);
    expect(coordinator.attachedUserId, 'user-1');
  });

  test('failure is contained and does not immediately retry', () async {
    var attempts = 0;

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (_) async {
        attempts++;
        throw StateError('attachment failed');
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(attempts, 1);
    expect(coordinator.attachedUserId, isNull);
    expect(coordinator.failedUserId, 'user-1');
    expect(coordinator.lastError, isA<StateError>());

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(attempts, 1);
  });

  test('sign-out clears failed state and permits later retry', () async {
    var shouldFail = true;
    var attempts = 0;

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (_) async {
        attempts++;

        if (shouldFail) {
          throw StateError('attachment failed');
        }
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(coordinator.failedUserId, 'user-1');

    coordinator.updateUserId(null);
    await coordinator.settled;

    shouldFail = false;

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(attempts, 2);
    expect(coordinator.attachedUserId, 'user-1');
    expect(coordinator.failedUserId, isNull);
  });

  test('account change during attachment does not attach stale user', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];

    final coordinator = AccountSyncOwnershipAttachmentCoordinator(
      attachUnowned: (userId) async {
        calls.add(userId);

        if (userId == 'user-1') {
          started.complete();
          await release.future;
        }
      },
    );

    coordinator.updateUserId('user-1');

    await started.future;

    coordinator.updateUserId('user-2');

    release.complete();

    await coordinator.settled;

    expect(calls, ['user-1', 'user-2']);
    expect(coordinator.currentUserId, 'user-2');
    expect(coordinator.attachedUserId, 'user-2');
  });
}
