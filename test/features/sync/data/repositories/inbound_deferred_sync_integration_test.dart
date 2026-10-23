import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_processor.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

// SN-47 H1/D1 and H2/D2 regressions against the real SQLite schema.
// Deferred rows are read with raw SQL so this file exercises only the
// public inbound entry points.
const _deferredTable = 'sync_inbound_deferred_records';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late _EntityPageReader reader;
  late InboundSyncReconciler reconciler;
  late InboundSyncProcessor processor;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;
    runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
    reader = _EntityPageReader();

    reconciler = InboundSyncReconciler(
      reader: reader,
      localSyncRepository: SqliteLocalSyncRepository(
        dao: LocalSyncDao(db),
        generateId: () => 'unused-outbox-id',
        now: () => DateTime.utc(2026, 10, 23, 12),
      ),
      mutationRunner: runner,
      now: () => DateTime.utc(2026, 10, 23, 12),
    );

    processor = InboundSyncProcessor(
      reconciler: reconciler,
      replayWindow: Duration.zero,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<int?> baseline(CloudDataEntity type, String id) {
    return runner.run(
      (context) => context.cloudRevisionBaselineRepository!.getRevision(
        userId: 'user-1',
        entityType: type,
        entityId: id,
      ),
    );
  }

  Future<String?> cursorId(CloudDataEntity type) async {
    final cursor = await runner.run(
      (context) => context.localSyncRepository.getCursor('user-1', type),
    );

    return cursor?.lastServerId;
  }

  Future<List<Map<String, Object?>>> deferredRows() async {
    final db = await appDatabase.database;

    return db.query(_deferredTable, orderBy: 'entity_type, entity_id');
  }

  test(
    'cloud artwork no longer aborts inbound sync and is durably deferred',
    () async {
      reader.pages[CloudDataEntity.artworkAsset] = [
        _artworkItem('artwork-1', revision: 3, at: _at(10)),
      ];

      reader.pages[CloudDataEntity.artist] = [
        _artistItem(
          'artist-1',
          revision: 2,
          at: _at(11),
          headerArtworkId: 'artwork-1',
        ),
        _artistItem('artist-2', revision: 1, at: _at(12)),
      ];

      final processed = await processor.pullAll(userId: 'user-1');

      expect(processed, 3);

      // Unaffected records still apply.
      final artist2 = await runner.run(
        (context) => context.artistRepository.getById('artist-2'),
      );
      expect(artist2?.name, 'Artist artist-2');
      expect(await baseline(CloudDataEntity.artist, 'artist-2'), 1);

      // Deferred records are not applied and get no baseline.
      final artist1 = await runner.run(
        (context) => context.artistRepository.getById('artist-1'),
      );
      expect(artist1, isNull);
      expect(await baseline(CloudDataEntity.artworkAsset, 'artwork-1'), isNull);
      expect(await baseline(CloudDataEntity.artist, 'artist-1'), isNull);

      // Cursors advance only alongside a durable replay obligation.
      expect(await cursorId(CloudDataEntity.artworkAsset), 'artwork-1');
      expect(await cursorId(CloudDataEntity.artist), 'artist-2');

      final rows = await deferredRows();
      expect(rows, hasLength(2));
      expect(rows[0]['entity_type'], 'artist');
      expect(rows[0]['entity_id'], 'artist-1');
      expect(rows[0]['server_revision'], 2);
      expect(rows[0]['reason'], 'missingLocalArtwork');
      expect(rows[1]['entity_type'], 'artworkAsset');
      expect(rows[1]['entity_id'], 'artwork-1');
      expect(rows[1]['server_revision'], 3);
      expect(rows[1]['reason'], 'artworkDownloadRequired');
    },
  );

  test('cloud artwork already held locally is reconciled', () async {
    await runner.run<void>((context) async {
      await context.artworkAssetRepository.create(_localArtwork('artwork-1'));
    });

    reader.pages[CloudDataEntity.artworkAsset] = [
      _artworkItem('artwork-1', revision: 2, at: _at(10)),
    ];
    reader.pages[CloudDataEntity.artist] = [
      _artistItem(
        'artist-1',
        revision: 1,
        at: _at(11),
        headerArtworkId: 'artwork-1',
      ),
    ];

    await processor.pullAll(userId: 'user-1');

    expect(await baseline(CloudDataEntity.artworkAsset, 'artwork-1'), 2);
    expect(await baseline(CloudDataEntity.artist, 'artist-1'), 1);
    expect(await deferredRows(), isEmpty);
  });

  test(
    'artist tombstone no longer aborts inbound sync or deletes local data',
    () async {
      await runner.run<void>((context) async {
        await context.artistRepository.create(_localArtist('artist-1'));
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 4,
        );
      });

      reader.pages[CloudDataEntity.artist] = [
        _artistItem('artist-1', revision: 5, at: _at(10), deleted: true),
        _artistItem('artist-2', revision: 1, at: _at(11)),
      ];

      await processor.pullAll(userId: 'user-1');

      final artist1 = await runner.run(
        (context) => context.artistRepository.getById('artist-1'),
      );
      expect(artist1?.name, 'Local artist-1');
      expect(await baseline(CloudDataEntity.artist, 'artist-1'), 4);
      expect(await baseline(CloudDataEntity.artist, 'artist-2'), 1);
      expect(await cursorId(CloudDataEntity.artist), 'artist-2');

      final rows = await deferredRows();
      expect(rows, hasLength(1));
      expect(rows.single['entity_id'], 'artist-1');
      expect(rows.single['server_revision'], 5);
      expect(rows.single['reason'], 'tombstoneRequiresLocalDeletion');
    },
  );

  test('tombstone for an artist never held locally is reconciled', () async {
    reader.pages[CloudDataEntity.artist] = [
      _artistItem('artist-9', revision: 3, at: _at(10), deleted: true),
    ];

    await processor.pullAll(userId: 'user-1');

    final artist = await runner.run(
      (context) => context.artistRepository.getById('artist-9'),
    );
    expect(artist, isNull);
    expect(await baseline(CloudDataEntity.artist, 'artist-9'), 3);
    expect(await deferredRows(), isEmpty);
  });

  test('a later applied revision clears its deferral', () async {
    reader.pages[CloudDataEntity.artist] = [
      _artistItem(
        'artist-1',
        revision: 2,
        at: _at(10),
        headerArtworkId: 'artwork-1',
      ),
    ];

    await processor.pullAll(userId: 'user-1');
    expect(await deferredRows(), hasLength(1));

    await runner.run<void>((context) async {
      await context.artworkAssetRepository.create(_localArtwork('artwork-1'));
    });

    reader.pages[CloudDataEntity.artist] = [
      _artistItem(
        'artist-1',
        revision: 3,
        at: _at(11),
        headerArtworkId: 'artwork-1',
      ),
    ];

    await processor.pullAll(userId: 'user-1');

    final artist = await runner.run(
      (context) => context.artistRepository.getById('artist-1'),
    );
    expect(artist?.headerArtworkId, 'artwork-1');
    expect(await baseline(CloudDataEntity.artist, 'artist-1'), 3);
    expect(await deferredRows(), isEmpty);
  });

  test('re-reading a deferred revision does not duplicate it', () async {
    reader.pages[CloudDataEntity.artworkAsset] = [
      _artworkItem('artwork-1', revision: 3, at: _at(10)),
    ];

    await processor.pullAll(userId: 'user-1');
    await processor.pullAll(userId: 'user-1');

    final rows = await deferredRows();
    expect(rows, hasLength(1));
    expect(rows.single['server_revision'], 3);
  });
}

DateTime _at(int hour) => DateTime.utc(2026, 10, 23, hour);

CloudSyncItem _artworkItem(
  String id, {
  required int revision,
  required DateTime at,
}) {
  return CloudSyncItem(
    record: CloudArtworkAssetRecord(
      id: id,
      userId: 'user-1',
      storageObjectKey: 'user-1/$id.png',
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 21),
    ),
    serverUpdatedAt: at,
    serverRevision: revision,
  );
}

CloudSyncItem _artistItem(
  String id, {
  required int revision,
  required DateTime at,
  String? headerArtworkId,
  bool deleted = false,
}) {
  return CloudSyncItem(
    record: CloudArtistRecord(
      id: id,
      userId: 'user-1',
      name: 'Artist $id',
      canonicalName: 'artist $id',
      headerArtworkId: headerArtworkId,
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 21),
      deletedAt: deleted ? at : null,
    ),
    serverUpdatedAt: at,
    serverRevision: revision,
  );
}

Artist _localArtist(String id) {
  return Artist(
    id: id,
    name: 'Local $id',
    canonicalName: 'local $id',
    createdAt: DateTime.utc(2026, 10, 20),
    updatedAt: DateTime.utc(2026, 10, 21),
  );
}

ArtworkAsset _localArtwork(String id) {
  return ArtworkAsset(
    id: id,
    filePath: '/artwork/$id.png',
    normalizedPath: '/artwork/$id.png',
    createdAt: DateTime.utc(2026, 10, 20),
    updatedAt: DateTime.utc(2026, 10, 21),
  );
}

/// Serves one fixed page per entity type, honoring the read position.
class _EntityPageReader implements CloudSyncReader {
  final Map<CloudDataEntity, List<CloudSyncItem>> pages = {};

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    final items = (pages[entityType] ?? const <CloudSyncItem>[])
        .where((item) {
          if (fromServerUpdatedAtInclusive != null) {
            return !item.serverUpdatedAt.isBefore(fromServerUpdatedAtInclusive);
          }

          if (after == null) {
            return true;
          }

          final comparison = item.serverUpdatedAt.compareTo(
            after.serverUpdatedAt,
          );

          return comparison > 0 ||
              (comparison == 0 && item.record.id.compareTo(after.id) > 0);
        })
        .take(limit)
        .toList();

    return CloudSyncPage(items: items, hasMore: false);
  }
}
