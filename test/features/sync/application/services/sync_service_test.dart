import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  var clockIndex = 0;

  final clockValues = [
    DateTime.utc(2026, 10, 6, 12),
    DateTime.utc(2026, 10, 6, 12, 0, 5),
  ];

  setUp(() {
    clockIndex = 0;
  });

  test('runs safe sync in bind, claim, push, pull order', () async {
    final calls = <String>[];

    var pendingReads = 0;

    final service = SyncService.forTesting(
      bindToUser: (userId) async {
        calls.add('bind:$userId');
      },
      claimUnowned: (userId) async {
        calls.add('claim:$userId');
        return 2;
      },
      getPending: (userId) async {
        calls.add('pending:$userId');

        pendingReads++;

        if (pendingReads == 1) {
          return [_entry('entry-1', userId), _entry('entry-2', userId)];
        }

        return const [];
      },
      pushPending: (userId) async {
        calls.add('push:$userId');
      },
      pullAll: (userId) async {
        calls.add('pull:$userId');
        return 7;
      },
      now: () => clockValues[clockIndex++],
    );

    final result = await service.synchronize(' user-1 ');

    expect(calls, [
      'bind:user-1',
      'claim:user-1',
      'pending:user-1',
      'push:user-1',
      'pull:user-1',
      'pending:user-1',
    ]);

    expect(result.userId, 'user-1');
    expect(result.claimedUnownedCount, 2);
    expect(result.pendingBeforePush, 2);
    expect(result.pushedMutationCount, 2);
    expect(result.pulledRecordCount, 7);
    expect(result.pendingAfterSync, 0);
    expect(result.hasRemainingPendingChanges, isFalse);
    expect(result.startedAt, clockValues[0]);
    expect(result.completedAt, clockValues[1]);
  });

  test('atomic attachment replaces separate bind and claim calls', () async {
    final calls = <String>[];

    final service = SyncService.forTesting(
      bindToUser: (_) async {
        calls.add('legacy-bind');
      },
      claimUnowned: (_) async {
        calls.add('legacy-claim');
        return 99;
      },
      attachAccount: (userId) async {
        calls.add('atomic:$userId');
        return 3;
      },
      getPending: (_) async {
        calls.add('pending');
        return const [];
      },
      pushPending: (_) async {
        calls.add('push');
      },
      pullAll: (_) async {
        calls.add('pull');
        return 0;
      },
      now: () => DateTime.utc(2026, 10, 15, 12),
    );

    final result = await service.synchronize(' user-1 ');

    expect(result.claimedUnownedCount, 3);
    expect(calls, ['atomic:user-1', 'pending', 'push', 'pull', 'pending']);
  });

  test('atomic attachment failure stops sync before cloud access', () async {
    final calls = <String>[];

    final service = SyncService.forTesting(
      bindToUser: (_) async {
        calls.add('legacy-bind');
      },
      claimUnowned: (_) async {
        calls.add('legacy-claim');
        return 0;
      },
      attachAccount: (userId) async {
        calls.add('atomic:$userId');
        throw StateError('Simulated atomic attachment failure');
      },
      getPending: (_) async {
        calls.add('pending');
        return const [];
      },
      pushPending: (_) async {
        calls.add('push');
      },
      pullAll: (_) async {
        calls.add('pull');
        return 0;
      },
    );

    await expectLater(
      service.synchronize('user-1'),
      throwsA(isA<StateError>()),
    );

    expect(calls, ['atomic:user-1']);
  });

  test('reports pending mutations that remain after sync', () async {
    var pendingReads = 0;

    final service = SyncService.forTesting(
      bindToUser: (_) async {},
      claimUnowned: (_) async => 0,
      getPending: (userId) async {
        pendingReads++;

        if (pendingReads == 1) {
          return [_entry('entry-1', userId)];
        }

        return [_entry('entry-2', userId)];
      },
      pushPending: (_) async {},
      pullAll: (_) async => 0,
      now: () => DateTime.utc(2026, 10, 6, 12),
    );

    final result = await service.synchronize('user-1');

    expect(result.pendingBeforePush, 1);
    expect(result.pendingAfterSync, 1);
    expect(result.hasRemainingPendingChanges, isTrue);
  });

  test('rejects blank user id before doing any sync work', () async {
    var called = false;

    final service = SyncService.forTesting(
      bindToUser: (_) async {
        called = true;
      },
      claimUnowned: (_) async => 0,
      getPending: (_) async => const [],
      pushPending: (_) async {},
      pullAll: (_) async => 0,
    );

    await expectLater(
      () => service.synchronize('   '),
      throwsA(isA<ArgumentError>()),
    );

    expect(called, isFalse);
  });

  test('does not push or pull when account binding is rejected', () async {
    var claimed = false;
    var pushed = false;
    var pulled = false;

    final service = SyncService.forTesting(
      bindToUser: (_) async {
        throw StateError('account conflict');
      },
      claimUnowned: (_) async {
        claimed = true;
        return 0;
      },
      getPending: (_) async => const [],
      pushPending: (_) async {
        pushed = true;
      },
      pullAll: (_) async {
        pulled = true;
        return 0;
      },
    );

    await expectLater(
      () => service.synchronize('user-2'),
      throwsA(isA<StateError>()),
    );

    expect(claimed, isFalse);
    expect(pushed, isFalse);
    expect(pulled, isFalse);
  });

  test('does not pull when outbound push fails', () async {
    var pulled = false;

    final service = SyncService.forTesting(
      bindToUser: (_) async {},
      claimUnowned: (_) async => 0,
      getPending: (userId) async => [_entry('entry-1', userId)],
      pushPending: (_) async {
        throw StateError('push failed');
      },
      pullAll: (_) async {
        pulled = true;
        return 0;
      },
    );

    await expectLater(
      () => service.synchronize('user-1'),
      throwsA(isA<StateError>()),
    );

    expect(pulled, isFalse);
  });

  test(
    'pulls immediately after a successful push with no pending work',
    () async {
      final calls = <String>[];

      final service = SyncService.forTesting(
        bindToUser: (_) async {},
        claimUnowned: (_) async => 0,
        getPending: (_) async => const [],
        pushPending: (_) async {
          calls.add('push');
        },
        pullAll: (_) async {
          calls.add('pull');
          return 3;
        },
        now: () => DateTime.utc(2026, 10, 6, 12),
      );

      final result = await service.synchronize('user-1');

      expect(calls, ['push', 'pull']);
      expect(result.pendingBeforePush, 0);
      expect(result.pulledRecordCount, 3);
    },
  );
}

SyncOutboxEntry _entry(String id, String userId) {
  final timestamp = DateTime.utc(2026, 10, 6, 12);

  return SyncOutboxEntry(
    id: id,
    userId: userId,
    entityType: CloudDataEntity.song,
    entityId: 'song-$id',
    operation: SyncOutboxOperation.upsert,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
