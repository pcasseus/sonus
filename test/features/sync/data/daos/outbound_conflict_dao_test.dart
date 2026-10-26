import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/inbound_deferred_record_dao.dart';
import 'package:sonus_next/features/sync/data/daos/outbound_conflict_dao.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/outbound_sync_conflict.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  OutboundSyncConflict conflict({
    int mutationRevision = 1,
    int? observed = 6,
    OutboundConflictCloudState state = OutboundConflictCloudState.live,
  }) {
    return OutboundSyncConflict(
      userId: 'u1',
      entityType: CloudDataEntity.album,
      entityId: 'album-1',
      outboxId: 'outbox-1',
      mutationRevision: mutationRevision,
      operation: SyncOutboxOperation.upsert,
      expectedServerRevision: 4,
      observedServerRevision: observed,
      observedState: state,
      detectedAt: DateTime.utc(2026, 10, 23, 12),
    );
  }

  group('OutboundConflictDao', () {
    late AppDatabase appDatabase;
    late OutboundConflictDao dao;

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      dao = OutboundConflictDao(await appDatabase.database);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('round-trips, replaces and clears one conflict per entity', () async {
      await dao.record(conflict());
      await dao.record(
        conflict(
          mutationRevision: 2,
          observed: null,
          state: OutboundConflictCloudState.absent,
        ),
      );

      final stored = (await dao.getAll('u1')).single;
      expect(stored.mutationRevision, 2);
      expect(stored.observedServerRevision, isNull);
      expect(stored.observedState, OutboundConflictCloudState.absent);
      expect(stored.expectedServerRevision, 4);
      expect(stored.operation, SyncOutboxOperation.upsert);
      expect(await dao.getAll('u2'), isEmpty);

      await dao.clear(
        userId: 'u1',
        entityType: CloudDataEntity.album,
        entityId: 'album-1',
      );
      expect(
        await dao.get(
          userId: 'u1',
          entityType: CloudDataEntity.album,
          entityId: 'album-1',
        ),
        isNull,
      );
    });

    test('schema rejects invalid states and revisions', () async {
      final db = await appDatabase.database;
      Map<String, Object?> row() => {
        'user_id': 'u1',
        'entity_type': 'album',
        'entity_id': 'album-1',
        'outbox_id': 'outbox-1',
        'mutation_revision': 1,
        'operation': 'upsert',
        'expected_server_revision': null,
        'observed_server_revision': null,
        'observed_state': 'live',
        'detected_at': '2026-10-23T12:00:00.000Z',
      };

      for (final invalid in [
        {'observed_state': 'unknown'},
        {'operation': 'merge'},
        {'mutation_revision': 0},
        {'observed_server_revision': 0},
      ]) {
        await expectLater(
          db.insert(SyncSchema.outboundConflictsTable, {...row(), ...invalid}),
          throwsA(isA<DatabaseException>()),
        );
      }
    });
  });

  test('version 32 upgrade preserves deferred rows and adds the conflict '
      'ledger', () async {
    final directory = await Directory.systemTemp.createTemp('sonus_v33_');
    final location = '${directory.path}/sonus.db';

    // The v32 ledger exactly as b43b39b created it.
    final old = await databaseFactoryFfi.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 32,
        onCreate: (db, version) async {
          await SyncSchema.createSyncOutbox(db);
          await SyncSchema.createCloudRevisionBaselines(db);
          await db.execute('''
              CREATE TABLE sync_inbound_deferred_records (
                user_id TEXT NOT NULL CHECK (length(trim(user_id)) > 0),
                entity_type TEXT NOT NULL CHECK (
                  entity_type IN (
                    'artworkAsset', 'artist', 'album', 'albumEdition', 'song'
                  )
                ),
                entity_id TEXT NOT NULL CHECK (length(trim(entity_id)) > 0),
                server_revision INTEGER NOT NULL CHECK (server_revision >= 1),
                server_updated_at TEXT NOT NULL
                  CHECK (length(trim(server_updated_at)) > 0),
                reason TEXT NOT NULL CHECK (
                  reason IN (
                    'artworkDownloadRequired',
                    'tombstoneRequiresLocalDeletion',
                    'missingLocalArtwork'
                  )
                ),
                deferred_at TEXT NOT NULL CHECK (length(trim(deferred_at)) > 0),
                PRIMARY KEY (user_id, entity_type, entity_id)
              )
            ''');
        },
      ),
    );

    try {
      await old.insert('sync_inbound_deferred_records', {
        'user_id': 'u1',
        'entity_type': 'artworkAsset',
        'entity_id': 'artwork-1',
        'server_revision': 3,
        'server_updated_at': '2026-10-23T10:00:00.000Z',
        'reason': 'artworkDownloadRequired',
        'deferred_at': '2026-10-23T11:00:00.000Z',
      });
    } finally {
      await old.close();
    }

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final db = await upgraded.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        AppDatabase.databaseVersion,
      );

      final deferredDao = InboundDeferredRecordDao(db);
      final preserved = (await deferredDao.getDeferred('u1')).single;
      expect(preserved.entityId, 'artwork-1');
      expect(preserved.serverRevision, 3);
      expect(preserved.reason, InboundDeferralReason.artworkDownloadRequired);

      // Reasons added in v33 are now accepted.
      for (final reason in [
        InboundDeferralReason.missingLocalParent,
        InboundDeferralReason.parentDeferred,
        InboundDeferralReason.pendingLocalMutation,
        InboundDeferralReason.unresolvedArtistJournal,
      ]) {
        await deferredDao.saveDeferred(
          InboundDeferredRecord(
            userId: 'u1',
            entityType: CloudDataEntity.song,
            entityId: 'song-${reason.name}',
            serverRevision: 1,
            serverUpdatedAt: DateTime.utc(2026, 10, 23),
            reason: reason,
            deferredAt: DateTime.utc(2026, 10, 23),
          ),
        );
      }
      expect(await deferredDao.getDeferred('u1'), hasLength(5));

      expect(
        await deferredDao.getDeferral(
          userId: 'u1',
          entityType: CloudDataEntity.artworkAsset,
          entityId: 'artwork-1',
        ),
        isNotNull,
      );

      await OutboundConflictDao(db).record(conflict());
      expect(await OutboundConflictDao(db).getAll('u1'), hasLength(1));
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
}
