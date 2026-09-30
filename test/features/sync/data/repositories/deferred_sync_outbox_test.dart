import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteLocalSyncRepository repository;

  var idCounter = 0;
  var now = DateTime.utc(2026, 9, 30, 12);

  setUp(() async {
    idCounter = 0;
    now = DateTime.utc(2026, 9, 30, 12);

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
      generateId: () => 'outbox_${++idCounter}',
      now: () => now,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('records signed-out mutation without inventing a user id', () async {
    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.artist,
      entityId: 'artist_1',
    );

    final rows = await database.query(DatabaseTables.syncOutbox);

    expect(rows, hasLength(1));
    expect(rows.single['user_id'], isNull);
    expect(rows.single['entity_type'], CloudDataEntity.artist.name);
    expect(rows.single['entity_id'], 'artist_1');
    expect(rows.single['operation'], 'upsert');
  });

  test('blank user id is normalized to unowned mutation', () async {
    await repository.recordUpsert(
      userId: '   ',
      entityType: CloudDataEntity.song,
      entityId: 'song_1',
    );

    final rows = await database.query(DatabaseTables.syncOutbox);

    expect(rows, hasLength(1));
    expect(rows.single['user_id'], isNull);
  });

  test('repeated unowned mutations collapse to one row', () async {
    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.song,
      entityId: 'song_1',
    );

    now = DateTime.utc(2026, 9, 30, 13);

    await repository.recordDelete(
      userId: null,
      entityType: CloudDataEntity.song,
      entityId: 'song_1',
    );

    final rows = await database.query(DatabaseTables.syncOutbox);

    expect(rows, hasLength(1));
    expect(rows.single['id'], 'outbox_1');
    expect(rows.single['user_id'], isNull);
    expect(rows.single['operation'], 'delete');
    expect(rows.single['created_at'], '2026-09-30T12:00:00.000Z');
    expect(rows.single['updated_at'], '2026-09-30T13:00:00.000Z');
  });

  test('claimUnowned attaches anonymous mutations to real account', () async {
    await repository.recordDelete(
      userId: null,
      entityType: CloudDataEntity.artist,
      entityId: 'artist_deleted',
    );

    final claimed = await repository.claimUnowned(' user_1 ');

    expect(claimed, 1);

    final pending = await repository.getPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.userId, 'user_1');
    expect(pending.single.entityId, 'artist_deleted');
    expect(pending.single.operation.name, 'delete');

    final unowned = await database.query(
      DatabaseTables.syncOutbox,
      where: 'user_id IS NULL',
    );

    expect(unowned, isEmpty);
  });

  test(
    'claim merges with existing owned mutation and latest operation wins',
    () async {
      await repository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.album,
        entityId: 'album_1',
      );

      now = DateTime.utc(2026, 9, 30, 13);

      await repository.recordDelete(
        userId: null,
        entityType: CloudDataEntity.album,
        entityId: 'album_1',
      );

      final claimed = await repository.claimUnowned('user_1');

      expect(claimed, 1);

      final pending = await repository.getPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.id, 'outbox_1');
      expect(pending.single.operation.name, 'delete');
      expect(pending.single.createdAt, DateTime.utc(2026, 9, 30, 12));
      expect(pending.single.updatedAt, DateTime.utc(2026, 9, 30, 13));
    },
  );

  test(
    'claim preserves newer owned mutation over older anonymous mutation',
    () async {
      await repository.recordDelete(
        userId: null,
        entityType: CloudDataEntity.albumEdition,
        entityId: 'edition_1',
      );

      now = DateTime.utc(2026, 9, 30, 13);

      await repository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.albumEdition,
        entityId: 'edition_1',
      );

      final claimed = await repository.claimUnowned('user_1');

      expect(claimed, 1);

      final pending = await repository.getPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.operation.name, 'upsert');
      expect(pending.single.createdAt, DateTime.utc(2026, 9, 30, 12));
      expect(pending.single.updatedAt, DateTime.utc(2026, 9, 30, 13));
    },
  );

  test('claim rejects blank account id', () async {
    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.artist,
      entityId: 'artist_1',
    );

    await expectLater(
      repository.claimUnowned('   '),
      throwsA(isA<ArgumentError>()),
    );

    final rows = await database.query(DatabaseTables.syncOutbox);

    expect(rows.single['user_id'], isNull);
  });
}
