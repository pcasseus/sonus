import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteLocalSyncRepository repository;

  var nextId = 0;
  var now = DateTime.utc(2026, 9, 13, 12);

  setUp(() async {
    nextId = 0;
    now = DateTime.utc(2026, 9, 13, 12);

    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await SyncSchema.create(db);
        },
      ),
    );

    repository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(database),
      generateId: () => 'outbox_${++nextId}',
      now: () => now,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('records an upsert with generated identity and timestamp', () async {
    await repository.recordUpsert(
      userId: 'user_1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist_1',
    );

    final pending = await repository.getPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.id, 'outbox_1');
    expect(pending.single.userId, 'user_1');
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, 'artist_1');
    expect(pending.single.operation, SyncOutboxOperation.upsert);
    expect(pending.single.createdAt, now);
    expect(pending.single.updatedAt, now);
  });

  test('records a delete', () async {
    await repository.recordDelete(
      userId: 'user_1',
      entityType: CloudDataEntity.song,
      entityId: 'song_1',
    );

    final pending = await repository.getPending('user_1');

    expect(pending.single.operation, SyncOutboxOperation.delete);
  });

  test('collapses repeated mutations through the DAO', () async {
    await repository.recordUpsert(
      userId: 'user_1',
      entityType: CloudDataEntity.album,
      entityId: 'album_1',
    );

    now = DateTime.utc(2026, 9, 13, 13);

    await repository.recordDelete(
      userId: 'user_1',
      entityType: CloudDataEntity.album,
      entityId: 'album_1',
    );

    final pending = await repository.getPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.id, 'outbox_1');
    expect(pending.single.operation, SyncOutboxOperation.delete);
    expect(pending.single.createdAt, DateTime.utc(2026, 9, 13, 12));
    expect(pending.single.updatedAt, DateTime.utc(2026, 9, 13, 13));
  });

  test('saves and reads entity-specific cursor', () async {
    final cursor = SyncCursor(
      userId: 'user_1',
      entityType: CloudDataEntity.artworkAsset,
      lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 14),
      lastServerId: 'artwork_20',
      updatedAt: DateTime.utc(2026, 9, 13, 14, 1),
    );

    await repository.saveCursor(cursor);

    final result = await repository.getCursor(
      'user_1',
      CloudDataEntity.artworkAsset,
    );

    expect(result!.lastServerId, 'artwork_20');
  });

  test('marks an outbox entry as processed', () async {
    await repository.recordUpsert(
      userId: 'user_1',
      entityType: CloudDataEntity.song,
      entityId: 'song_1',
    );

    final pending = await repository.getPending('user_1');

    await repository.markProcessed(
      userId: 'user_1',
      outboxEntryId: pending.single.id,
    );

    expect(await repository.getPending('user_1'), isEmpty);
  });
}
