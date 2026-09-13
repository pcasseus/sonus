import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late LocalSyncDao dao;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await SyncSchema.create(db);
        },
      ),
    );

    dao = LocalSyncDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('cursor persistence', () {
    test('returns null when no cursor exists', () async {
      final result = await dao.findCursor('user_1', CloudDataEntity.artist);

      expect(result, isNull);
    });

    test('round-trips a cursor', () async {
      final cursor = SyncCursor(
        userId: 'user_1',
        entityType: CloudDataEntity.artist,
        lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 12),
        lastServerId: 'artist_10',
        updatedAt: DateTime.utc(2026, 9, 13, 12, 1),
      );

      await dao.saveCursor(cursor);

      final result = await dao.findCursor('user_1', CloudDataEntity.artist);

      expect(result, isNotNull);
      expect(result!.userId, 'user_1');
      expect(result.entityType, CloudDataEntity.artist);
      expect(result.lastServerUpdatedAt, DateTime.utc(2026, 9, 13, 12));
      expect(result.lastServerId, 'artist_10');
      expect(result.updatedAt, DateTime.utc(2026, 9, 13, 12, 1));
    });

    test('keeps independent cursors for each cloud entity', () async {
      await dao.saveCursor(
        SyncCursor(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 10),
          lastServerId: 'artist_1',
          updatedAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.saveCursor(
        SyncCursor(
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 11),
          lastServerId: 'album_1',
          updatedAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      final artistCursor = await dao.findCursor(
        'user_1',
        CloudDataEntity.artist,
      );
      final albumCursor = await dao.findCursor('user_1', CloudDataEntity.album);

      expect(artistCursor!.lastServerId, 'artist_1');
      expect(albumCursor!.lastServerId, 'album_1');
    });

    test('replaces the cursor for the same user and entity', () async {
      await dao.saveCursor(
        SyncCursor(
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 8),
          lastServerId: 'song_1',
          updatedAt: DateTime.utc(2026, 9, 13, 8),
        ),
      );

      await dao.saveCursor(
        SyncCursor(
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 9),
          lastServerId: 'song_2',
          updatedAt: DateTime.utc(2026, 9, 13, 9),
        ),
      );

      final result = await dao.findCursor('user_1', CloudDataEntity.song);

      expect(result!.lastServerId, 'song_2');
      expect(result.lastServerUpdatedAt, DateTime.utc(2026, 9, 13, 9));
    });

    test('keeps cursors isolated by user', () async {
      await dao.saveCursor(
        SyncCursor(
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          lastServerUpdatedAt: DateTime.utc(2026, 9, 13, 8),
          lastServerId: 'album_1',
          updatedAt: DateTime.utc(2026, 9, 13, 8),
        ),
      );

      final otherUser = await dao.findCursor('user_2', CloudDataEntity.album);

      expect(otherUser, isNull);
    });
  });

  group('outbox persistence', () {
    SyncOutboxEntry entry({
      required String id,
      required String userId,
      required CloudDataEntity entityType,
      required String entityId,
      required SyncOutboxOperation operation,
      required DateTime createdAt,
      DateTime? updatedAt,
    }) {
      return SyncOutboxEntry(
        id: id,
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        createdAt: createdAt,
        updatedAt: updatedAt ?? createdAt,
      );
    }

    test('returns pending entries in creation order', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_2',
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          entityId: 'song_2',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      await dao.enqueue(
        entry(
          id: 'outbox_1',
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      final result = await dao.findPending('user_1');

      expect(result.map((value) => value.id), ['outbox_1', 'outbox_2']);
    });

    test('keeps pending entries isolated by user', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_1',
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.enqueue(
        entry(
          id: 'outbox_2',
          userId: 'user_2',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_2',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      final result = await dao.findPending('user_1');

      expect(result, hasLength(1));
      expect(result.single.id, 'outbox_1');
    });

    test('collapses upsert then delete to one delete entry', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_original',
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          entityId: 'song_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.enqueue(
        entry(
          id: 'outbox_replacement',
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          entityId: 'song_1',
          operation: SyncOutboxOperation.delete,
          createdAt: DateTime.utc(2026, 9, 13, 11),
          updatedAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      final result = await dao.findPending('user_1');

      expect(result, hasLength(1));
      expect(result.single.id, 'outbox_original');
      expect(result.single.operation, SyncOutboxOperation.delete);
      expect(result.single.createdAt, DateTime.utc(2026, 9, 13, 10));
      expect(result.single.updatedAt, DateTime.utc(2026, 9, 13, 11));
    });

    test('collapses delete then upsert to one upsert entry', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_original',
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          entityId: 'album_1',
          operation: SyncOutboxOperation.delete,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.enqueue(
        entry(
          id: 'outbox_replacement',
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          entityId: 'album_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 11),
          updatedAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      final result = await dao.findPending('user_1');

      expect(result, hasLength(1));
      expect(result.single.id, 'outbox_original');
      expect(result.single.operation, SyncOutboxOperation.upsert);
      expect(result.single.createdAt, DateTime.utc(2026, 9, 13, 10));
    });

    test('does not collapse different entity types with the same id', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_artist',
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'shared_id',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.enqueue(
        entry(
          id: 'outbox_album',
          userId: 'user_1',
          entityType: CloudDataEntity.album,
          entityId: 'shared_id',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      final result = await dao.findPending('user_1');

      expect(result, hasLength(2));
    });

    test('removes a processed outbox entry', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_1',
          userId: 'user_1',
          entityType: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 10),
        ),
      );

      await dao.removeOutboxEntry(userId: 'user_1', id: 'outbox_1');

      expect(await dao.findPending('user_1'), isEmpty);
    });

    test('cannot remove another user outbox entry', () async {
      await dao.enqueue(
        entry(
          id: 'outbox_other_user',
          userId: 'user_1',
          entityType: CloudDataEntity.song,
          entityId: 'song_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: DateTime.utc(2026, 9, 13, 11),
        ),
      );

      await dao.removeOutboxEntry(userId: 'user_2', id: 'outbox_other_user');

      final pending = await dao.findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.id, 'outbox_other_user');
    });
  });
}
