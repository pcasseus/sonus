import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/app/account_analytics_attachment_coordinator.dart';

void main() {
  test('attaches active analytics before historical analytics', () async {
    final calls = <String>[];

    final coordinator = AccountAnalyticsAttachmentCoordinator(
      attachActiveSession: (userId) async {
        calls.add('active:$userId');
      },
      attachHistoricalAnalytics: (userId) async {
        calls.add('historical:$userId');
      },
    );

    coordinator.updateUserId(' user-1 ');

    await coordinator.settled;

    expect(calls, ['active:user-1', 'historical:user-1']);

    expect(coordinator.attachedUserId, 'user-1');
    expect(coordinator.failedUserId, isNull);
    expect(coordinator.lastError, isNull);
  });

  test('repeated notification for attached user is idempotent', () async {
    var activeCalls = 0;
    var historicalCalls = 0;

    final coordinator = AccountAnalyticsAttachmentCoordinator(
      attachActiveSession: (_) async {
        activeCalls++;
      },
      attachHistoricalAnalytics: (_) async {
        historicalCalls++;
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(activeCalls, 1);
    expect(historicalCalls, 1);
  });

  test('sign-out resets attachment so same user can attach again', () async {
    var activeCalls = 0;
    var historicalCalls = 0;

    final coordinator = AccountAnalyticsAttachmentCoordinator(
      attachActiveSession: (_) async {
        activeCalls++;
      },
      attachHistoricalAnalytics: (_) async {
        historicalCalls++;
      },
    );

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    coordinator.updateUserId(null);
    await coordinator.settled;

    expect(coordinator.attachedUserId, isNull);

    coordinator.updateUserId('user-1');
    await coordinator.settled;

    expect(activeCalls, 2);
    expect(historicalCalls, 2);
    expect(coordinator.attachedUserId, 'user-1');
  });

  test('failure is contained and does not immediately retry', () async {
    var attempts = 0;

    final coordinator = AccountAnalyticsAttachmentCoordinator(
      attachActiveSession: (_) async {
        attempts++;
        throw StateError('attachment failed');
      },
      attachHistoricalAnalytics: (_) async {
        fail('Historical attachment must not run.');
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

  test('sign-out clears failed state and permits a later retry', () async {
    var shouldFail = true;
    var activeCalls = 0;
    var historicalCalls = 0;

    final coordinator = AccountAnalyticsAttachmentCoordinator(
      attachActiveSession: (_) async {
        activeCalls++;

        if (shouldFail) {
          throw StateError('attachment failed');
        }
      },
      attachHistoricalAnalytics: (_) async {
        historicalCalls++;
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

    expect(activeCalls, 2);
    expect(historicalCalls, 1);
    expect(coordinator.attachedUserId, 'user-1');
    expect(coordinator.failedUserId, isNull);
  });

  test(
    'account change during active attachment does not attach old history',
    () async {
      final activeStarted = Completer<void>();
      final releaseActive = Completer<void>();

      final calls = <String>[];

      final coordinator = AccountAnalyticsAttachmentCoordinator(
        attachActiveSession: (userId) async {
          calls.add('active:$userId');

          if (userId == 'user-1') {
            activeStarted.complete();
            await releaseActive.future;
          }
        },
        attachHistoricalAnalytics: (userId) async {
          calls.add('historical:$userId');
        },
      );

      coordinator.updateUserId('user-1');

      await activeStarted.future;

      coordinator.updateUserId(null);

      releaseActive.complete();

      await coordinator.settled;

      expect(calls, ['active:user-1']);
      expect(coordinator.currentUserId, isNull);
      expect(coordinator.attachedUserId, isNull);
    },
  );
}
