import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/inbound_deferred_record_dao.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  const table = SyncSchema.inboundDeferredRecordsTable;

  InboundDeferredRecord record({
    int revision = 2,
    String entityId = 'artist-1',
    InboundDeferralReason reason = InboundDeferralReason.missingLocalArtwork,
  }) {
    return InboundDeferredRecord(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: entityId,
      serverRevision: revision,
      serverUpdatedAt: DateTime.utc(2026, 10, 23, 10, revision),
      reason: reason,
      deferredAt: DateTime.utc(2026, 10, 23, 12),
    );
  }

  group('InboundDeferredRecordDao', () {
    late AppDatabase appDatabase;
    late InboundDeferredRecordDao dao;

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      dao = InboundDeferredRecordDao(await appDatabase.database);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('round-trips a deferral', () async {
      await dao.saveDeferred(record());

      final stored = (await dao.getDeferred('user-1')).single;

      expect(stored.entityType, CloudDataEntity.artist);
      expect(stored.entityId, 'artist-1');
      expect(stored.serverRevision, 2);
      expect(stored.serverUpdatedAt, DateTime.utc(2026, 10, 23, 10, 2));
      expect(stored.reason, InboundDeferralReason.missingLocalArtwork);
      expect(await dao.getDeferred('user-2'), isEmpty);
    });

    test('a newer revision replaces an older deferral', () async {
      await dao.saveDeferred(record(revision: 2));
      await dao.saveDeferred(
        record(
          revision: 3,
          reason: InboundDeferralReason.tombstoneRequiresLocalDeletion,
        ),
      );

      final stored = (await dao.getDeferred('user-1')).single;
      expect(stored.serverRevision, 3);
      expect(
        stored.reason,
        InboundDeferralReason.tombstoneRequiresLocalDeletion,
      );
    });

    test('an older revision never regresses a deferral', () async {
      await dao.saveDeferred(record(revision: 5));
      await dao.saveDeferred(record(revision: 4));

      expect((await dao.getDeferred('user-1')).single.serverRevision, 5);
    });

    test('clears only through the applied revision', () async {
      await dao.saveDeferred(record(revision: 5));

      await dao.clearThroughRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 4,
      );
      expect(await dao.getDeferred('user-1'), hasLength(1));

      await dao.clearThroughRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 5,
      );
      expect(await dao.getDeferred('user-1'), isEmpty);
    });

    test('schema rejects unknown reasons and invalid revisions', () async {
      final db = await appDatabase.database;

      Map<String, Object?> row({String reason = 'missingLocalArtwork'}) => {
        'user_id': 'user-1',
        'entity_type': 'artist',
        'entity_id': 'artist-1',
        'server_revision': 1,
        'server_updated_at': '2026-10-23T10:00:00.000Z',
        'reason': reason,
        'deferred_at': '2026-10-23T12:00:00.000Z',
      };

      await expectLater(
        db.insert(table, row(reason: 'skipped')),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(table, {...row(), 'server_revision': 0}),
        throwsA(isA<DatabaseException>()),
      );
    });

    group('requeueDeferral', () {
      final later = DateTime.utc(2026, 10, 23, 15);

      Future<bool> requeue({int revision = 2, String entityId = 'artist-1'}) {
        return dao.requeueDeferral(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: entityId,
          serverRevision: revision,
          deferredAt: later,
        );
      }

      test('moves only the deferral time of the same revision', () async {
        await dao.saveDeferred(record());

        expect(await requeue(), isTrue);

        final stored = (await dao.getDeferred('user-1')).single;
        expect(stored.serverRevision, 2);
        expect(stored.reason, InboundDeferralReason.missingLocalArtwork);
        expect(stored.serverUpdatedAt, DateTime.utc(2026, 10, 23, 10, 2));
        expect(stored.deferredAt, later);
      });

      test('never downgrades or touches a newer revision', () async {
        await dao.saveDeferred(
          record(revision: 5, reason: InboundDeferralReason.parentDeferred),
        );

        expect(await requeue(revision: 2), isFalse);

        final stored = (await dao.getDeferred('user-1')).single;
        expect(stored.serverRevision, 5);
        expect(stored.reason, InboundDeferralReason.parentDeferred);
        expect(stored.deferredAt, DateTime.utc(2026, 10, 23, 12));
      });

      test('never revives a cleared obligation', () async {
        expect(await requeue(), isFalse);
        expect(await dao.getDeferred('user-1'), isEmpty);
      });
    });
  });

  test('version 31 upgrade adds the ledger and keeps sync state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_deferred_upgrade_',
    );
    final location = '${directory.path}/sonus.db';

    final oldDatabase = await databaseFactoryFfi.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 31,
        onCreate: (db, version) async {
          await SyncSchema.createSyncOutbox(db);
          await SyncSchema.createCloudRevisionBaselines(db);
        },
      ),
    );

    try {
      await oldDatabase.insert(DatabaseTables.syncOutbox, {
        'id': 'existing_outbox',
        'user_id': 'user-1',
        'entity_type': 'album',
        'entity_id': 'album-1',
        'operation': 'upsert',
        'created_at': '2026-10-23T10:00:00.000Z',
        'updated_at': '2026-10-23T10:00:00.000Z',
        'mutation_revision': 2,
      });
      await oldDatabase.insert(SyncSchema.cloudRevisionBaselinesTable, {
        'user_id': 'user-1',
        'entity_type': 'album',
        'entity_id': 'album-1',
        'server_revision': 6,
      });
    } finally {
      await oldDatabase.close();
    }

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final db = await upgraded.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        34,
      );
      expect(await db.query(DatabaseTables.syncOutbox), hasLength(1));
      expect(
        (await db.query(
          SyncSchema.cloudRevisionBaselinesTable,
        )).single['server_revision'],
        6,
      );

      await InboundDeferredRecordDao(db).saveDeferred(record());
      expect(await db.query(table), hasLength(1));
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
}
