import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_processor.dart';
import 'package:sonus_next/features/sync/application/services/inbound_sync_reconciler.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

// SN-47 A2 item 1: a child is never applied ahead of a parent that is
// missing locally or deferred. Exercised against real SQLite foreign keys.
void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late _EntityPageReader reader;
  late InboundSyncProcessor processor;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await appDatabase.database;
    runner = SyncMutationTransactionRunner(appDatabase: appDatabase);
    reader = _EntityPageReader();

    processor = InboundSyncProcessor(
      reconciler: InboundSyncReconciler(
        reader: reader,
        localSyncRepository: SqliteLocalSyncRepository(
          dao: LocalSyncDao(db),
          generateId: () => 'unused-outbox-id',
          now: () => _at(12),
        ),
        mutationRunner: runner,
        now: () => _at(12),
      ),
      replayWindow: Duration.zero,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Map<CloudDataEntity, InboundDeferralReason>> deferrals() async {
    final records = await runner.run(
      (context) => context.inboundDeferredRecordRepository!.getDeferred('u1'),
    );

    return {for (final record in records) record.entityType: record.reason};
  }

  Future<List<Object?>> localChain() {
    return runner.run(
      (context) async => [
        await context.artistRepository.getById('artist-1'),
        await context.albumRepository.getById('album-1'),
        await context.albumEditionRepository.getById('edition-1'),
        await context.songRepository.getById('song-1'),
      ],
    );
  }

  Future<String?> cursorId(CloudDataEntity type) async {
    final cursor = await runner.run(
      (context) => context.localSyncRepository.getCursor('u1', type),
    );

    return cursor?.lastServerId;
  }

  test(
    'deferred artist defers album, edition and song without FK failure',
    () async {
      // The artist references artwork this device does not hold.
      reader.seedChain(artistHeaderArtworkId: 'missing-artwork');

      final processed = await processor.pullAll(userId: 'u1');

      expect(processed, 4);
      expect(await localChain(), [null, null, null, null]);
      expect(await deferrals(), {
        CloudDataEntity.artist: InboundDeferralReason.missingLocalArtwork,
        CloudDataEntity.album: InboundDeferralReason.missingLocalParent,
        CloudDataEntity.albumEdition: InboundDeferralReason.missingLocalParent,
        CloudDataEntity.song: InboundDeferralReason.missingLocalParent,
      });

      // Every cursor advanced only alongside its replay obligation.
      expect(await cursorId(CloudDataEntity.artist), 'artist-1');
      expect(await cursorId(CloudDataEntity.album), 'album-1');
      expect(await cursorId(CloudDataEntity.albumEdition), 'edition-1');
      expect(await cursorId(CloudDataEntity.song), 'song-1');

      final baselines = await runner.run(
        (context) async => [
          for (final type in CloudDataEntity.values)
            await context.cloudRevisionBaselineRepository!.getRevision(
              userId: 'u1',
              entityType: type,
              entityId: switch (type) {
                CloudDataEntity.artist => 'artist-1',
                CloudDataEntity.album => 'album-1',
                CloudDataEntity.albumEdition => 'edition-1',
                CloudDataEntity.song => 'song-1',
                CloudDataEntity.artworkAsset => 'missing-artwork',
              },
            ),
        ],
      );
      expect(baselines.every((revision) => revision == null), isTrue);
    },
  );

  test('locally held but deferred artist still defers its album', () async {
    await runner.run<void>((context) async {
      await context.artistRepository.create(
        Artist(
          id: 'artist-1',
          name: 'Local Artist',
          canonicalName: 'local artist',
          createdAt: _at(1),
          updatedAt: _at(1),
        ),
      );
      await context.cloudRevisionBaselineRepository!.saveObservedRevision(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 1,
      );
    });

    // Revision 2 of the held artist references missing artwork.
    reader.seedChain(
      artistHeaderArtworkId: 'missing-artwork',
      artistRevision: 2,
    );

    await processor.pullAll(userId: 'u1');

    final chain = await localChain();
    expect((chain[0] as Artist?)?.name, 'Local Artist');
    expect(chain.sublist(1), [null, null, null]);
    expect(await deferrals(), {
      CloudDataEntity.artist: InboundDeferralReason.missingLocalArtwork,
      CloudDataEntity.album: InboundDeferralReason.parentDeferred,
      CloudDataEntity.albumEdition: InboundDeferralReason.missingLocalParent,
      // The song's artist is checked first: held locally but deferred.
      CloudDataEntity.song: InboundDeferralReason.parentDeferred,
    });
  });

  test('a complete chain with available parents applies in order', () async {
    reader.seedChain();

    await processor.pullAll(userId: 'u1');

    final chain = await localChain();
    expect(chain.every((entity) => entity != null), isTrue);
    expect(await deferrals(), isEmpty);
  });

  test('re-reading a deferred chain does not duplicate or abort', () async {
    reader.seedChain(artistHeaderArtworkId: 'missing-artwork');

    await processor.pullAll(userId: 'u1');
    await processor.pullAll(userId: 'u1');

    expect(await deferrals(), hasLength(4));
    expect(await localChain(), [null, null, null, null]);
  });
}

DateTime _at(int hour) => DateTime.utc(2026, 10, 23, hour);

class _EntityPageReader implements CloudSyncReader {
  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    CloudSyncItem? current;

    for (final item in pages[entityType] ?? const <CloudSyncItem>[]) {
      if (item.record.userId == userId &&
          item.record.id == entityId &&
          (current == null ||
              (item.serverRevision ?? 0) > (current.serverRevision ?? 0))) {
        current = item;
      }
    }

    return current;
  }

  final Map<CloudDataEntity, List<CloudSyncItem>> pages = {};

  void seedChain({String? artistHeaderArtworkId, int artistRevision = 1}) {
    CloudSyncItem item(CloudOwnedRecord record, int hour, int revision) {
      return CloudSyncItem(
        record: record,
        serverUpdatedAt: _at(hour),
        serverRevision: revision,
      );
    }

    pages[CloudDataEntity.artist] = [
      item(
        CloudArtistRecord(
          id: 'artist-1',
          userId: 'u1',
          name: 'Cloud Artist',
          canonicalName: 'cloud artist',
          headerArtworkId: artistHeaderArtworkId,
          createdAt: _at(1),
          updatedAt: _at(2),
        ),
        3,
        artistRevision,
      ),
    ];
    pages[CloudDataEntity.album] = [
      item(
        CloudAlbumRecord(
          id: 'album-1',
          userId: 'u1',
          artistId: 'artist-1',
          title: 'Album',
          canonicalTitle: 'album',
          createdAt: _at(1),
          updatedAt: _at(2),
        ),
        4,
        1,
      ),
    ];
    pages[CloudDataEntity.albumEdition] = [
      item(
        CloudAlbumEditionRecord(
          id: 'edition-1',
          userId: 'u1',
          albumId: 'album-1',
          title: 'Standard',
          type: 'standard',
          isPrimary: true,
          createdAt: _at(1),
          updatedAt: _at(2),
        ),
        5,
        1,
      ),
    ];
    pages[CloudDataEntity.song] = [
      item(
        CloudSongRecord(
          id: 'song-1',
          userId: 'u1',
          artistId: 'artist-1',
          albumId: 'album-1',
          albumEditionId: 'edition-1',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 1,
          durationSeconds: 200,
          isSingle: false,
          featuredArtists: const [],
          createdAt: _at(1),
          updatedAt: _at(2),
        ),
        6,
        1,
      ),
    ];
  }

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    final items = (pages[entityType] ?? const <CloudSyncItem>[]).where((item) {
      if (fromServerUpdatedAtInclusive != null) {
        return !item.serverUpdatedAt.isBefore(fromServerUpdatedAtInclusive);
      }

      if (after == null) {
        return true;
      }

      final comparison = item.serverUpdatedAt.compareTo(after.serverUpdatedAt);

      return comparison > 0 ||
          (comparison == 0 && item.record.id.compareTo(after.id) > 0);
    });

    return CloudSyncPage(items: items.take(limit).toList(), hasMore: false);
  }
}
