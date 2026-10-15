import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/app/account_sync_ownership_attachment_service.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/data/repositories/sqlite_local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('attaches unowned mutations to normalized account id', () async {
    final db = await appDatabase.database;

    var nextId = 0;

    final repository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(db),
      generateId: () => 'outbox_${++nextId}',
      now: () => DateTime.utc(2026, 9, 30, 12),
    );

    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.song,
      entityId: 'song-1',
    );

    await repository.recordDelete(
      userId: null,
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );

    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    final attached = await service.attachUnownedToUser(' user-1 ');

    expect(attached, 2);

    final owned = await LocalSyncDao(db).findPending('user-1');
    final unowned = await LocalSyncDao(db).findUnownedPending();

    expect(owned, hasLength(2));
    expect(unowned, isEmpty);
    expect(owned.map((entry) => entry.userId).toSet(), {'user-1'});

    final binding = await SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    ).getBinding();

    expect(binding, isNotNull);
    expect(binding!.userId, 'user-1');
  });

  test(
    'binds first account even when there are no unowned mutations',
    () async {
      final service = AccountSyncOwnershipAttachmentService(
        appDatabase: appDatabase,
      );

      final attached = await service.attachUnownedToUser('user-1');

      expect(attached, 0);

      final binding = await SqliteLocalAccountBindingRepository(
        appDatabase: appDatabase,
      ).getBinding();

      expect(binding, isNotNull);
      expect(binding!.userId, 'user-1');
    },
  );

  test('allows the same account to attach again', () async {
    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    await service.attachUnownedToUser('user-1');

    final attached = await service.attachUnownedToUser(' user-1 ');

    expect(attached, 0);

    final binding = await SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    ).getBinding();

    expect(binding!.userId, 'user-1');
  });

  test('rejects a different account before claiming anonymous work', () async {
    final db = await appDatabase.database;

    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    await service.attachUnownedToUser('user-1');

    final repository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(db),
      generateId: () => 'outbox-1',
      now: () => DateTime.utc(2026, 10, 6, 12),
    );

    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.song,
      entityId: 'song-1',
    );

    await expectLater(
      () => service.attachUnownedToUser('user-2'),
      throwsA(
        isA<LocalAccountBindingConflict>()
            .having((error) => error.boundUserId, 'boundUserId', 'user-1')
            .having(
              (error) => error.requestedUserId,
              'requestedUserId',
              'user-2',
            ),
      ),
    );

    final unowned = await LocalSyncDao(db).findUnownedPending();
    final secondAccountPending = await LocalSyncDao(db).findPending('user-2');

    expect(unowned, hasLength(1));
    expect(secondAccountPending, isEmpty);

    final binding = await SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    ).getBinding();

    expect(binding!.userId, 'user-1');
  });

  test('failed ownership claim rolls back new account binding', () async {
    final db = await appDatabase.database;

    final repository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(db),
      generateId: () => 'rollback_outbox_1',
      now: () => DateTime.utc(2026, 10, 15, 12),
    );

    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.song,
      entityId: 'rollback_song',
    );

    // Reject the ownership transfer after the transaction has
    // already inserted the new account-binding row.
    await db.execute('''
      CREATE TRIGGER reject_outbox_claim
      BEFORE UPDATE OF user_id ON sync_outbox
      WHEN OLD.user_id IS NULL AND NEW.user_id IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'Simulated ownership claim failure');
      END
    ''');

    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    await expectLater(
      service.attachUnownedToUser('user-1'),
      throwsA(isA<Exception>()),
    );

    final bindingRepository = SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    );

    // Neither half of the operation should have committed.
    expect(await bindingRepository.getBinding(), isNull);

    final unownedAfterFailure = await LocalSyncDao(db).findUnownedPending();
    final ownedAfterFailure = await LocalSyncDao(db).findPending('user-1');

    expect(unownedAfterFailure, hasLength(1));
    expect(unownedAfterFailure.single.entityId, 'rollback_song');
    expect(ownedAfterFailure, isEmpty);

    // Remove the injected database failure and retry normally.
    await db.execute('DROP TRIGGER reject_outbox_claim');

    final claimed = await service.attachUnownedToUser('user-1');

    expect(claimed, 1);
    expect((await bindingRepository.getBinding())?.userId, 'user-1');
    expect(await LocalSyncDao(db).findUnownedPending(), isEmpty);

    final ownedAfterRetry = await LocalSyncDao(db).findPending('user-1');

    expect(ownedAfterRetry, hasLength(1));
    expect(ownedAfterRetry.single.entityId, 'rollback_song');
    expect(ownedAfterRetry.single.mutationRevision, 1);
  });

  test('rejects blank account id before opening claim', () async {
    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    await expectLater(
      () => service.attachUnownedToUser('   '),
      throwsA(isA<ArgumentError>()),
    );

    final binding = await SqliteLocalAccountBindingRepository(
      appDatabase: appDatabase,
    ).getBinding();

    expect(binding, isNull);
  });
}
