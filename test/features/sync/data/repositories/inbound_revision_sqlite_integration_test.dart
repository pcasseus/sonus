import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  test(
    'real inbound reconciliation commits success and preserves it on failure',
    () async {
      final appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

      try {
        final db = await appDatabase.database;
        final runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
        final reader = _TestCloudReader();

        final reconciler = InboundSyncReconciler(
          reader: reader,
          localSyncRepository: SqliteLocalSyncRepository(
            dao: LocalSyncDao(db),
            generateId: () => 'test-sync-outbox-id',
            now: () => DateTime.utc(2026, 10, 16, 12),
          ),
          mutationRunner: runner,
        );

        final firstTimestamp = DateTime.utc(2026, 10, 16, 10);
        final secondTimestamp = DateTime.utc(2026, 10, 16, 11);

        reader.page = CloudSyncPage(
          items: [
            _artistItem(
              'artist-1',
              serverRevision: 8,
              serverUpdatedAt: firstTimestamp,
            ),
          ],
          hasMore: false,
        );

        final firstResult = await reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        );

        expect(firstResult.processedCount, 1);

        await runner.run<void>((context) async {
          final artist = await context.artistRepository.getById('artist-1');
          final revision = await context.cloudRevisionBaselineRepository!
              .getRevision(
                userId: 'user-1',
                entityType: CloudDataEntity.artist,
                entityId: 'artist-1',
              );
          final cursor = await context.localSyncRepository.getCursor(
            'user-1',
            CloudDataEntity.artist,
          );

          expect(artist?.name, 'Artist artist-1');
          expect(revision, 8);
          expect(cursor?.lastServerId, 'artist-1');
        });

        // A pending local mutation rejects the record. That failure
        // must not acknowledge the later cloud record.
        await runner.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-2',
          );
        });

        reader.page = CloudSyncPage(
          items: [
            _artistItem(
              'artist-2',
              serverRevision: 9,
              serverUpdatedAt: secondTimestamp,
            ),
          ],
          hasMore: false,
        );

        await expectLater(
          reconciler.reconcilePage(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            limit: 10,
          ),
          throwsStateError,
        );

        await runner.run<void>((context) async {
          final firstArtist = await context.artistRepository.getById(
            'artist-1',
          );
          final failedArtist = await context.artistRepository.getById(
            'artist-2',
          );

          final firstRevision = await context.cloudRevisionBaselineRepository!
              .getRevision(
                userId: 'user-1',
                entityType: CloudDataEntity.artist,
                entityId: 'artist-1',
              );

          final failedRevision = await context.cloudRevisionBaselineRepository!
              .getRevision(
                userId: 'user-1',
                entityType: CloudDataEntity.artist,
                entityId: 'artist-2',
              );

          final cursor = await context.localSyncRepository.getCursor(
            'user-1',
            CloudDataEntity.artist,
          );

          expect(firstArtist?.name, 'Artist artist-1');
          expect(failedArtist, isNull);
          expect(firstRevision, 8);
          expect(failedRevision, isNull);
          expect(cursor?.lastServerId, 'artist-1');
          expect(cursor?.lastServerUpdatedAt, firstTimestamp);
        });
      } finally {
        await appDatabase.close();
      }
    },
  );
  test('real pending outbox prevents inbound artist overwrite', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await appDatabase.database;
      final runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
      final reader = _TestCloudReader();

      final reconciler = InboundSyncReconciler(
        reader: reader,
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(db),
          generateId: () => 'pending-artist-outbox',
          now: () => DateTime.utc(2026, 10, 16, 12),
        ),
        mutationRunner: runner,
      );

      final previousTimestamp = DateTime.utc(2026, 10, 16, 9);

      await runner.run<void>((context) async {
        await context.artistRepository.create(
          Artist(
            id: 'artist-1',
            name: 'Protected Local Artist',
            canonicalName: 'protected local artist',
            createdAt: DateTime.utc(2026, 10, 15),
            updatedAt: DateTime.utc(2026, 10, 16),
          ),
        );

        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 7,
        );

        await context.localSyncRepository.saveCursor(
          SyncCursor(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            lastServerUpdatedAt: previousTimestamp,
            lastServerId: 'artist-0',
            updatedAt: previousTimestamp,
          ),
        );

        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });

      reader.page = CloudSyncPage(
        items: [
          _artistItem(
            'artist-1',
            serverRevision: 8,
            serverUpdatedAt: DateTime.utc(2026, 10, 16, 10),
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsStateError,
      );

      await runner.run<void>((context) async {
        final artist = await context.artistRepository.getById('artist-1');

        final revision = await context.cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );

        final cursor = await context.localSyncRepository.getCursor(
          'user-1',
          CloudDataEntity.artist,
        );

        final pending = await context.localSyncRepository.getPending('user-1');

        expect(artist?.name, 'Protected Local Artist');
        expect(revision, 7);
        expect(cursor?.lastServerUpdatedAt, previousTimestamp);
        expect(cursor?.lastServerId, 'artist-0');

        expect(pending, hasLength(1));
        expect(pending.single.entityType, CloudDataEntity.artist);
        expect(pending.single.entityId, 'artist-1');
        expect(pending.single.operation, SyncOutboxOperation.upsert);
      });
    } finally {
      await appDatabase.close();
    }
  });
  test('invalid revision is rejected before pending outbox conflict', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await appDatabase.database;
      final runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
      final reader = _TestCloudReader();

      final reconciler = InboundSyncReconciler(
        reader: reader,
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(db),
          generateId: () => 'invalid-revision-outbox',
          now: () => DateTime.utc(2026, 10, 16, 12),
        ),
        mutationRunner: runner,
      );

      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });

      // CloudSyncItem permits a nullable revision to preserve
      // compatibility at the reader-model boundary.
      reader.page = CloudSyncPage(
        items: [
          CloudSyncItem(
            record: CloudArtistRecord(
              id: 'artist-1',
              userId: 'user-1',
              name: 'Invalid Cloud Artist',
              canonicalName: 'invalid cloud artist',
              createdAt: DateTime.utc(2026, 10, 15),
              updatedAt: DateTime.utc(2026, 10, 16),
            ),
            serverUpdatedAt: DateTime.utc(2026, 10, 16, 10),
            serverRevision: null,
          ),
        ],
        hasMore: false,
      );

      await expectLater(
        reconciler.reconcilePage(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          limit: 10,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no valid server revision'),
          ),
        ),
      );

      await runner.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user-1');
        final artist = await context.artistRepository.getById('artist-1');
        final revision = await context.cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );
        final cursor = await context.localSyncRepository.getCursor(
          'user-1',
          CloudDataEntity.artist,
        );

        expect(pending, hasLength(1));
        expect(artist, isNull);
        expect(revision, isNull);
        expect(cursor, isNull);
      });
    } finally {
      await appDatabase.close();
    }
  });
}

CloudSyncItem _artistItem(
  String id, {
  required int serverRevision,
  required DateTime serverUpdatedAt,
  DateTime? deletedAt,
}) {
  return CloudSyncItem(
    record: CloudArtistRecord(
      id: id,
      userId: 'user-1',
      name: 'Artist $id',
      canonicalName: 'artist $id',
      createdAt: DateTime.utc(2026, 10, 15),
      updatedAt: DateTime.utc(2026, 10, 16),
      deletedAt: deletedAt,
    ),
    serverUpdatedAt: serverUpdatedAt,
    serverRevision: serverRevision,
  );
}

class _TestCloudReader implements CloudSyncReader {
  CloudSyncPage page = const CloudSyncPage(items: [], hasMore: false);

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    return page;
  }
}
