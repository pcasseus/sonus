import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/app/account_sync_ownership_attachment_service.dart';
import 'package:sonus_next/core/database/app_database.dart';
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
  });

  test('does nothing when there are no unowned mutations', () async {
    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    final attached = await service.attachUnownedToUser('user-1');

    expect(attached, 0);
  });

  test('rejects blank account id before opening claim', () async {
    final service = AccountSyncOwnershipAttachmentService(
      appDatabase: appDatabase,
    );

    await expectLater(
      () => service.attachUnownedToUser('   '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
