import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
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
      expect(pending.single.mutationRevision, 2);
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
      expect(pending.single.mutationRevision, 2);
      expect(pending.single.createdAt, DateTime.utc(2026, 9, 30, 12));
      expect(pending.single.updatedAt, DateTime.utc(2026, 9, 30, 13));
    },
  );

  test('concurrent enqueues retain every mutation revision', () async {
    const mutationCount = 25;

    await Future.wait(
      List.generate(
        mutationCount,
        (_) => repository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          entityId: 'song_concurrent',
        ),
      ),
    );

    final pending = await repository.getPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, 'song_concurrent');
    expect(pending.single.operation, SyncOutboxOperation.upsert);
    expect(pending.single.mutationRevision, mutationCount);

    final rows = await database.query(
      DatabaseTables.syncOutbox,
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: ['user_1', CloudDataEntity.song.name, 'song_concurrent'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['mutation_revision'], mutationCount);
  });

  test('ownership claim rollback preserves original outbox rows', () async {
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

    await repository.recordUpsert(
      userId: null,
      entityType: CloudDataEntity.artist,
      entityId: 'artist_1',
    );

    final before = await database.query(
      DatabaseTables.syncOutbox,
      orderBy: 'id ASC',
    );

    expect(before, hasLength(3));

    await expectLater(
      database.transaction((transaction) async {
        final transactionRepository = SqliteLocalSyncRepository(
          dao: LocalSyncDao(transaction),
          generateId: () => 'unused_transaction_id',
          now: () => now,
        );

        final claimed = await transactionRepository.claimUnowned('user_1');
        expect(claimed, 2);

        throw StateError('Simulated failure before commit');
      }),
      throwsA(isA<StateError>()),
    );

    final afterRollback = await database.query(
      DatabaseTables.syncOutbox,
      orderBy: 'id ASC',
    );

    expect(afterRollback, equals(before));

    final claimedOnRetry = await database.transaction((transaction) {
      final transactionRepository = SqliteLocalSyncRepository(
        dao: LocalSyncDao(transaction),
        generateId: () => 'unused_transaction_id',
        now: () => now,
      );

      return transactionRepository.claimUnowned('user_1');
    });

    expect(claimedOnRetry, 2);

    final pending = await repository.getPending('user_1');
    expect(pending, hasLength(2));

    final album = pending.singleWhere((entry) => entry.entityId == 'album_1');
    expect(album.operation, SyncOutboxOperation.delete);
    expect(album.mutationRevision, 2);

    final artist = pending.singleWhere((entry) => entry.entityId == 'artist_1');
    expect(artist.operation, SyncOutboxOperation.upsert);

    final remainingAnonymous = await database.query(
      DatabaseTables.syncOutbox,
      where: 'user_id IS NULL',
    );

    expect(remainingAnonymous, isEmpty);
  });

  test('unrelated outbox id collision preserves database error', () async {
    await repository.recordUpsert(
      userId: 'user_1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist_original',
    );

    final collidingRepository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(database),
      generateId: () => 'outbox_1',
      now: () => now,
    );

    await expectLater(
      collidingRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.song,
        entityId: 'song_different',
      ),
      throwsA(isA<DatabaseException>()),
    );

    final pending = await repository.getPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.id, 'outbox_1');
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, 'artist_original');
    expect(pending.single.operation, SyncOutboxOperation.upsert);
    expect(pending.single.mutationRevision, 1);
  });

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
