import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/repositories/outbound_conflict_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/outbound_sync_conflict.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

import 'outbound_sync_processor_test.dart'
    show
        FakeAlbumEditionRepository,
        FakeAlbumRepository,
        FakeArtistRepository,
        FakeArtworkAssetRepository,
        FakeCloudArtworkStorage,
        FakeCloudRevisionBaselineRepository,
        FakeLocalSyncRepository,
        FakeMetadataFieldStateRepository,
        FakeSongRepository,
        album,
        artist,
        artwork,
        edition,
        outbox;

// SN-47 A2 items 2-6: lost-response recovery, deterministic re-baseline,
// conditional deletes, immutable artwork and durable conflicts.
void main() {
  final timestamp = DateTime.utc(2026, 10, 23, 12);

  late FakeLocalSyncRepository localSync;
  late FakeArtistRepository artists;
  late FakeAlbumRepository albums;
  late FakeAlbumEditionRepository editions;
  late FakeArtworkAssetRepository artworks;
  late FakeMetadataFieldStateRepository metadata;
  late FakeCloudArtworkStorage storage;
  late _ScriptedGateway gateway;
  late FakeCloudRevisionBaselineRepository baselines;
  late _MemoryConflictRepository conflicts;

  setUp(() {
    localSync = FakeLocalSyncRepository();
    artists = FakeArtistRepository();
    albums = FakeAlbumRepository();
    editions = FakeAlbumEditionRepository();
    artworks = FakeArtworkAssetRepository();
    metadata = FakeMetadataFieldStateRepository();
    storage = FakeCloudArtworkStorage();
    gateway = _ScriptedGateway();
    baselines = FakeCloudRevisionBaselineRepository();
    conflicts = _MemoryConflictRepository();

    artists.values['artist_1'] = artist(timestamp);
    albums.values['album_1'] = album(timestamp);
    editions.values['edition_1'] = edition(timestamp);
    artworks.values['artwork_1'] = artwork(timestamp);
  });

  OutboundSyncProcessor processor({
    PushArtistMutation? pushArtistMutation,
    EnsureArtistDependency? ensureArtistDependency,
  }) {
    return OutboundSyncProcessor(
      localSyncRepository: localSync,
      artistRepository: artists,
      albumRepository: albums,
      albumEditionRepository: editions,
      songRepository: FakeSongRepository(),
      metadataFieldStateRepository: metadata,
      artworkAssetRepository: artworks,
      cloudArtworkStorage: storage,
      cloudSyncGateway: gateway,
      cloudRevisionBaselineRepository: baselines,
      pushArtistMutation:
          pushArtistMutation ??
          ({required userId, required entry, required artist}) async {
            throw StateError('Unexpected explicit artist upload.');
          },
      ensureArtistDependency:
          ensureArtistDependency ??
          ({required userId, required artist}) async {},
      outboundConflictRepository: conflicts,
      // In-memory stand-in; atomicity is proven against SQLite in
      // outbound_acknowledgement_atomicity_test.dart.
      acknowledgeEntry: ({required userId, required entry}) async {
        await localSync.markProcessed(
          userId: userId,
          outboxEntryId: entry.id,
          expectedRevision: entry.mutationRevision,
          expectedOperation: entry.operation,
        );
        await conflicts.clearResolved(
          userId: userId,
          entityType: entry.entityType,
          entityId: entry.entityId,
          outboxId: entry.id,
          mutationRevision: entry.mutationRevision,
        );
      },
      newArtworkVersion: () => 'dep-version',
      now: () => timestamp,
    );
  }

  void baseline(CloudDataEntity type, String id, int revision) {
    baselines.revisions['user_1:${type.name}:$id'] = revision;
  }

  int? baselineOf(CloudDataEntity type, String id) {
    return baselines.revisions['user_1:${type.name}:$id'];
  }

  void pendingAlbum({int mutationRevision = 1}) {
    localSync.pending.add(
      SyncOutboxEntry(
        id: 'outbox_album',
        userId: 'user_1',
        entityType: CloudDataEntity.album,
        entityId: 'album_1',
        operation: SyncOutboxOperation.upsert,
        createdAt: timestamp,
        updatedAt: timestamp,
        mutationRevision: mutationRevision,
      ),
    );
  }

  // The exact payload the processor sends for album_1.
  CloudAlbumRecord localAlbumPayload() {
    return CloudAlbumRecord(
      id: 'album_1',
      userId: 'user_1',
      artistId: 'artist_1',
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: timestamp,
      updatedAt: timestamp,
      metadataFieldStates: const [],
    );
  }

  void cloud(CloudOwnedRecord record, int revision, CloudDataEntity type) {
    gateway.currentRows['${type.name}:${record.id}'] = CloudSyncItem(
      record: record,
      serverUpdatedAt: timestamp,
      serverRevision: revision,
    );
  }

  group('lost response and deterministic re-baseline', () {
    test(
      'applied update whose response was lost is adopted on retry',
      () async {
        baseline(CloudDataEntity.artist, 'artist_1', 2);
        baseline(CloudDataEntity.album, 'album_1', 4);
        pendingAlbum();

        gateway.results['update:album:album_1@4'] = const _Conflict(5);
        cloud(localAlbumPayload(), 5, CloudDataEntity.album);

        await processor().pushPending('user_1');

        expect(baselineOf(CloudDataEntity.album, 'album_1'), 5);
        expect(localSync.processedIds, ['outbox_album']);
        expect(conflicts.values, isEmpty);
      },
    );

    test('lost insert response is adopted at revision 1', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      pendingAlbum();

      gateway.results['insert:album:album_1'] = const _Conflict(1);
      cloud(localAlbumPayload(), 1, CloudDataEntity.album);

      await processor().pushPending('user_1');

      expect(baselineOf(CloudDataEntity.album, 'album_1'), 1);
      expect(localSync.processedIds, ['outbox_album']);
    });

    test('baseline-less row with identical payload is re-baselined', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      pendingAlbum();

      gateway.results['insert:album:album_1'] = const _Conflict(9);
      cloud(localAlbumPayload(), 9, CloudDataEntity.album);

      await processor().pushPending('user_1');

      expect(baselineOf(CloudDataEntity.album, 'album_1'), 9);
      expect(localSync.processedIds, ['outbox_album']);
      expect(conflicts.values, isEmpty);
    });

    final mismatches = <String, CloudAlbumRecord Function(CloudAlbumRecord)>{
      'title': (r) => _album(r, title: 'Other'),
      'canonical title': (r) => _album(r, canonicalTitle: 'other'),
      'artist': (r) => _album(r, artistId: 'artist_2'),
      'updated at by one microsecond': (r) => _album(
        r,
        updatedAt: r.updatedAt.add(const Duration(microseconds: 1)),
      ),
      'created at': (r) =>
          _album(r, createdAt: r.createdAt.subtract(const Duration(days: 1))),
      'provenance never synced': (r) => _album(r, nullStates: true),
      'provenance source reference': (r) => _album(
        r,
        states: [
          CloudMetadataFieldState(
            fieldName: 'title',
            authority: 'manual',
            source: 'user',
            updatedAt: r.updatedAt,
            sourceReference: 'other',
          ),
        ],
      ),
    };

    for (final mismatch in mismatches.entries) {
      test('differing ${mismatch.key} is a conflict, never adopted', () async {
        baseline(CloudDataEntity.artist, 'artist_1', 2);
        baseline(CloudDataEntity.album, 'album_1', 4);
        pendingAlbum();

        gateway.results['update:album:album_1@4'] = const _Conflict(5);
        cloud(mismatch.value(localAlbumPayload()), 5, CloudDataEntity.album);

        await expectLater(
          processor().pushPending('user_1'),
          throwsA(isA<OutboundRecordWriteConflict>()),
        );

        expect(baselineOf(CloudDataEntity.album, 'album_1'), 4);
        expect(localSync.pending, hasLength(1));
        final conflict = conflicts.values.single;
        expect(conflict.observedState, OutboundConflictCloudState.live);
        expect(conflict.observedServerRevision, 5);
        expect(conflict.expectedServerRevision, 4);
        expect(conflict.outboxId, 'outbox_album');
      });
    }

    test('identical payload on a tombstone is a conflict', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      gateway.results['update:album:album_1@4'] = const _Conflict(5);
      cloud(
        _album(localAlbumPayload(), deletedAt: timestamp),
        5,
        CloudDataEntity.album,
      );

      await expectLater(
        processor().pushPending('user_1'),
        throwsA(isA<OutboundRecordWriteConflict>()),
      );

      expect(
        conflicts.values.single.observedState,
        OutboundConflictCloudState.tombstoned,
      );
      expect(localSync.pending, hasLength(1));
    });

    test('identical payload below the expected revision is a conflict', () {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      gateway.results['update:album:album_1@4'] = const _Conflict(4);
      cloud(localAlbumPayload(), 4, CloudDataEntity.album);

      return expectLater(
        processor().pushPending('user_1'),
        throwsA(isA<OutboundRecordWriteConflict>()),
      ).then((_) => expect(baselineOf(CloudDataEntity.album, 'album_1'), 4));
    });

    test('another account\'s identical row is never adopted', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      pendingAlbum();

      gateway.results['insert:album:album_1'] = const _Conflict(null);
      cloud(
        _album(localAlbumPayload(), userId: 'user_2'),
        1,
        CloudDataEntity.album,
      );

      await expectLater(
        processor().pushPending('user_1'),
        throwsA(isA<OutboundRecordWriteConflict>()),
      );

      expect(baselineOf(CloudDataEntity.album, 'album_1'), isNull);
      expect(
        conflicts.values.single.observedState,
        OutboundConflictCloudState.absent,
      );
    });

    test('a later successful push clears the recorded conflict', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      gateway.results['update:album:album_1@4'] = const _Conflict(5);
      cloud(
        _album(localAlbumPayload(), title: 'Other'),
        5,
        CloudDataEntity.album,
      );

      await expectLater(processor().pushPending('user_1'), throwsA(anything));
      expect(conflicts.values, hasLength(1));

      // Resolution moved the baseline to the observed revision.
      baseline(CloudDataEntity.album, 'album_1', 5);
      await processor().pushPending('user_1');

      expect(gateway.calls.last, 'update:album:album_1@5');
      expect(conflicts.values, isEmpty);
      expect(localSync.processedIds, ['outbox_album']);
    });

    test('retry after adoption performs no further cloud writes', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      gateway.results['update:album:album_1@4'] = const _Conflict(5);
      cloud(localAlbumPayload(), 5, CloudDataEntity.album);

      final run = processor();
      await run.pushPending('user_1');
      final callsAfterFirstRun = gateway.calls.length;
      await run.pushPending('user_1');

      expect(gateway.calls, hasLength(callsAfterFirstRun));
    });
  });

  group('concurrency', () {
    test('a local edit during an in-flight write stays pending', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      gateway.beforeWrite = (call) async {
        if (call == 'update:album:album_1@4') {
          localSync.pending[0] = SyncOutboxEntry(
            id: 'outbox_album',
            userId: 'user_1',
            entityType: CloudDataEntity.album,
            entityId: 'album_1',
            operation: SyncOutboxOperation.upsert,
            createdAt: timestamp,
            updatedAt: timestamp,
            mutationRevision: 2,
          );
        }
      };

      await processor().pushPending('user_1');

      // The cloud revision is recorded; the newer local edit survives and
      // will be written against it.
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 5);
      expect(localSync.processedIds, isEmpty);
      expect(localSync.pending.single.mutationRevision, 2);
    });

    test('concurrent runs on one processor write once', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      final release = Completer<void>();
      gateway.beforeWrite = (call) => release.future;

      final run = processor();
      final first = run.pushPending('user_1');
      final second = run.pushPending('user_1');
      release.complete();
      await Future.wait([first, second]);

      expect(
        gateway.calls.where((call) => call.startsWith('update:album')),
        hasLength(1),
      );
    });

    test('a competing device write wins and is never overwritten', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();

      // Another device advanced the row to revision 5 first.
      gateway.results['update:album:album_1@4'] = const _Conflict(5);
      cloud(
        _album(localAlbumPayload(), title: 'Theirs'),
        5,
        CloudDataEntity.album,
      );

      await expectLater(processor().pushPending('user_1'), throwsA(anything));

      expect(gateway.calls, ['update:album:album_1@4']);
      expect(
        (gateway.currentRows['album:album_1']!.record as CloudAlbumRecord)
            .title,
        'Theirs',
      );
    });
  });

  group('revision-conditional deletes', () {
    void pendingDelete(CloudDataEntity type, String id) {
      localSync.pending.add(
        outbox(
          id: 'outbox_delete',
          type: type,
          entityId: id,
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );
    }

    test('delete from a verified revision is acknowledged', () async {
      baseline(CloudDataEntity.album, 'album_1', 3);
      pendingDelete(CloudDataEntity.album, 'album_1');

      await processor().pushPending('user_1');

      expect(gateway.calls, ['conditionalDelete:album:album_1@3']);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 4);
      expect(localSync.processedIds, ['outbox_delete']);
    });

    test('stale delete never removes a newer cloud row', () async {
      baseline(CloudDataEntity.album, 'album_1', 3);
      pendingDelete(CloudDataEntity.album, 'album_1');

      gateway.results['conditionalDelete:album:album_1@3'] = const _Conflict(6);
      cloud(localAlbumPayload(), 6, CloudDataEntity.album);

      await expectLater(
        processor().pushPending('user_1'),
        throwsA(isA<OutboundRecordWriteConflict>()),
      );

      expect(gateway.currentRows['album:album_1']!.record.isDeleted, isFalse);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 3);
      expect(localSync.pending, hasLength(1));
      expect(conflicts.values.single.operation, SyncOutboxOperation.delete);
    });

    test('lost delete response is satisfied by the tombstone', () async {
      baseline(CloudDataEntity.album, 'album_1', 3);
      pendingDelete(CloudDataEntity.album, 'album_1');

      gateway.results['conditionalDelete:album:album_1@3'] = const _Conflict(4);
      cloud(
        _album(localAlbumPayload(), deletedAt: timestamp),
        4,
        CloudDataEntity.album,
      );

      await processor().pushPending('user_1');

      expect(baselineOf(CloudDataEntity.album, 'album_1'), 4);
      expect(localSync.processedIds, ['outbox_delete']);
    });

    test('delete of a row never synced makes no cloud write', () async {
      pendingDelete(CloudDataEntity.song, 'song_9');

      await processor().pushPending('user_1');

      expect(gateway.calls, isEmpty);
      expect(localSync.processedIds, ['outbox_delete']);
    });

    test('baseline-less delete of a live row is a conflict', () async {
      pendingDelete(CloudDataEntity.album, 'album_1');
      cloud(localAlbumPayload(), 2, CloudDataEntity.album);

      await expectLater(
        processor().pushPending('user_1'),
        throwsA(isA<OutboundRecordWriteConflict>()),
      );

      expect(gateway.calls, isEmpty);
      expect(localSync.pending, hasLength(1));
    });

    test('artist delete without receipts is also conditional', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 7);
      pendingDelete(CloudDataEntity.artist, 'artist_1');

      await processor().pushPending('user_1');

      expect(gateway.calls, ['conditionalDelete:artist:artist_1@7']);
      expect(baselineOf(CloudDataEntity.artist, 'artist_1'), 8);
    });
  });

  group('immutable artwork storage', () {
    void pendingArtwork() {
      localSync.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );
    }

    CloudArtworkAssetRecord artworkRow(String key) {
      return CloudArtworkAssetRecord(
        id: 'artwork_1',
        userId: 'user_1',
        storageObjectKey: key,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    }

    test('rejected row write leaves the accepted object untouched', () async {
      baseline(CloudDataEntity.artworkAsset, 'artwork_1', 2);
      pendingArtwork();

      gateway.results['update:artworkAsset:artwork_1@2'] = const _Conflict(3);
      cloud(
        artworkRow('user_1/artwork_1/accepted.png'),
        3,
        CloudDataEntity.artworkAsset,
      );

      await expectLater(processor().pushPending('user_1'), throwsA(anything));

      // Only the rejected attempt's own object is removed.
      expect(storage.calls, [
        'uploadImmutable:user_1:artwork_1:outbox_artwork-r1',
        'deleteObject:user_1/artwork_1/outbox_artwork-r1.png',
      ]);
      expect(
        (gateway.currentRows['artworkAsset:artwork_1']!.record
                as CloudArtworkAssetRecord)
            .storageObjectKey,
        'user_1/artwork_1/accepted.png',
      );
    });

    test('lost artwork response keeps and adopts its object', () async {
      baseline(CloudDataEntity.artworkAsset, 'artwork_1', 2);
      pendingArtwork();

      const key = 'user_1/artwork_1/outbox_artwork-r1.png';
      gateway.results['update:artworkAsset:artwork_1@2'] = const _Conflict(3);
      cloud(artworkRow(key), 3, CloudDataEntity.artworkAsset);

      await processor().pushPending('user_1');

      expect(storage.calls, [
        'uploadImmutable:user_1:artwork_1:outbox_artwork-r1',
      ]);
      expect(baselineOf(CloudDataEntity.artworkAsset, 'artwork_1'), 3);
      expect(localSync.processedIds, ['outbox_artwork']);
    });

    test('existing live artwork dependency is never re-uploaded', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 3);
      cloud(
        artworkRow('user_1/artwork_1/old.png'),
        4,
        CloudDataEntity.artworkAsset,
      );
      localSync.pending.add(
        outbox(
          id: 'outbox_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
      );

      await processor().pushPending('user_1');

      expect(storage.calls, isEmpty);
      expect(gateway.calls, ['insert:albumEdition:edition_1']);
    });

    test('dependency upload that loses a race removes its object', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 3);
      localSync.pending.add(
        outbox(
          id: 'outbox_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
      );

      // Another device inserts the artwork row between fetch and insert.
      gateway.results['insert:artworkAsset:artwork_1'] = const _Conflict(1);
      gateway.beforeWrite = (call) async {
        if (call == 'insert:artworkAsset:artwork_1') {
          cloud(
            artworkRow('user_1/artwork_1/theirs.png'),
            1,
            CloudDataEntity.artworkAsset,
          );
        }
      };

      await processor().pushPending('user_1');

      expect(storage.calls, [
        'uploadImmutable:user_1:artwork_1:dep-version',
        'deleteObject:user_1/artwork_1/dep-version.png',
      ]);
      expect(gateway.calls.last, 'insert:albumEdition:edition_1');
      expect(localSync.processedIds, ['outbox_edition']);
    });
  });

  group('dependency safety', () {
    test('a child is never written under a tombstoned parent', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      localSync.pending.add(
        outbox(
          id: 'outbox_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
      );
      baseline(CloudDataEntity.artworkAsset, 'artwork_1', 1);

      gateway.results['insert:album:album_1'] = const _Conflict(3);
      cloud(
        _album(localAlbumPayload(), deletedAt: timestamp, title: 'Gone'),
        3,
        CloudDataEntity.album,
      );

      await expectLater(processor().pushPending('user_1'), throwsA(anything));

      expect(gateway.calls, isNot(contains('insert:albumEdition:edition_1')));
      expect(localSync.pending, hasLength(1));
    });

    test('baseline-less live artist satisfies an album dependency', () async {
      pendingAlbum();
      cloud(
        CloudArtistRecord(
          id: 'artist_1',
          userId: 'user_1',
          name: 'Cloud Artist',
          canonicalName: 'cloud artist',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        5,
        CloudDataEntity.artist,
      );

      await processor(
        ensureArtistDependency: ({required userId, required artist}) async {
          throw const OutboundArtistWriteConflict(
            artistId: 'artist_1',
            outcome: CloudConditionalWriteOutcome.conflict,
            expectedServerRevision: null,
            observedServerRevision: 5,
          );
        },
      ).pushPending('user_1');

      expect(gateway.calls, ['insert:album:album_1']);
      expect(baselineOf(CloudDataEntity.artist, 'artist_1'), isNull);
    });

    test('baseline-less tombstoned artist still blocks its album', () async {
      pendingAlbum();
      cloud(
        CloudArtistRecord(
          id: 'artist_1',
          userId: 'user_1',
          name: 'Gone',
          canonicalName: 'gone',
          createdAt: timestamp,
          updatedAt: timestamp,
          deletedAt: timestamp,
        ),
        5,
        CloudDataEntity.artist,
      );

      await expectLater(
        processor(
          ensureArtistDependency: ({required userId, required artist}) async {
            throw const OutboundArtistWriteConflict(
              artistId: 'artist_1',
              outcome: CloudConditionalWriteOutcome.conflict,
              expectedServerRevision: null,
              observedServerRevision: 5,
            );
          },
        ).pushPending('user_1'),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expect(gateway.calls, isEmpty);
    });

    test('explicit artist conflict is recorded durably', () async {
      localSync.pending.add(
        outbox(
          id: 'outbox_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      );
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      cloud(
        CloudArtistRecord(
          id: 'artist_1',
          userId: 'user_1',
          name: 'Theirs',
          canonicalName: 'theirs',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        3,
        CloudDataEntity.artist,
      );

      await expectLater(
        processor(
          pushArtistMutation:
              ({required userId, required entry, required artist}) async {
                throw const OutboundArtistWriteConflict(
                  artistId: 'artist_1',
                  outcome: CloudConditionalWriteOutcome.conflict,
                  expectedServerRevision: 2,
                  observedServerRevision: 3,
                );
              },
        ).pushPending('user_1'),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      final conflict = conflicts.values.single;
      expect(conflict.entityType, CloudDataEntity.artist);
      expect(conflict.expectedServerRevision, 2);
      expect(conflict.observedServerRevision, 3);
      expect(localSync.pending, hasLength(1));
    });
  });

  group('isolated push report', () {
    test('entry failures are reported, not thrown', () async {
      baseline(CloudDataEntity.artist, 'artist_1', 2);
      baseline(CloudDataEntity.album, 'album_1', 4);
      pendingAlbum();
      gateway.results['update:album:album_1@4'] = const _Conflict(5);

      final report = await processor().pushPendingIsolated('user_1');

      expect(report.isComplete, isFalse);
      expect(report.failures.single.entry.id, 'outbox_album');
      expect(report.failures.single.error, isA<OutboundRecordWriteConflict>());
    });

    test('ownership holds are still thrown before any write', () async {
      localSync.pending.add(
        SyncOutboxEntry(
          id: 'foreign',
          userId: 'user_2',
          entityType: CloudDataEntity.album,
          entityId: 'album_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );

      await expectLater(
        processor().pushPendingIsolated('user_1'),
        throwsStateError,
      );
      expect(gateway.calls, isEmpty);
    });
  });
}

CloudAlbumRecord _album(
  CloudAlbumRecord source, {
  String? userId,
  String? artistId,
  String? title,
  String? canonicalTitle,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  List<CloudMetadataFieldState>? states,
  bool nullStates = false,
}) {
  return CloudAlbumRecord(
    id: source.id,
    userId: userId ?? source.userId,
    artistId: artistId ?? source.artistId,
    title: title ?? source.title,
    canonicalTitle: canonicalTitle ?? source.canonicalTitle,
    createdAt: createdAt ?? source.createdAt,
    updatedAt: updatedAt ?? source.updatedAt,
    deletedAt: deletedAt ?? source.deletedAt,
    metadataFieldStates: nullStates
        ? null
        : states ?? source.metadataFieldStates,
  );
}

class _Conflict extends CloudConditionalWriteResult {
  const _Conflict(int? revision)
    : super(
        outcome: revision == null
            ? CloudConditionalWriteOutcome.notFound
            : CloudConditionalWriteOutcome.conflict,
        serverRevision: revision,
      );
}

class _ScriptedGateway implements CloudSyncGateway {
  final List<String> calls = [];
  final Map<String, CloudConditionalWriteResult> results = {};
  final Map<String, CloudSyncItem> currentRows = {};
  Future<void> Function(String call)? beforeWrite;

  Future<CloudConditionalWriteResult> _write(
    String call,
    CloudConditionalWriteResult defaultResult,
  ) async {
    calls.add(call);
    await beforeWrite?.call(call);
    return results[call] ?? defaultResult;
  }

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(CloudOwnedRecord record) {
    return _write(
      'insert:${_type(record)}:${record.id}',
      const CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.applied,
        serverRevision: 1,
      ),
    );
  }

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) {
    return _write(
      'update:${_type(record)}:${record.id}@$expectedServerRevision',
      CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.applied,
        serverRevision: expectedServerRevision + 1,
      ),
    );
  }

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) {
    return _write(
      'conditionalDelete:${entityType.name}:$entityId@$expectedServerRevision',
      CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.applied,
        serverRevision: expectedServerRevision + 1,
      ),
    );
  }

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final item = currentRows['${entityType.name}:$entityId'];

    // Row-level security never returns another account's row.
    return item == null || item.record.userId != userId ? null : item;
  }

  @override
  Future<void> upsert(CloudOwnedRecord record) {
    throw StateError('Guarded sync must never upsert unconditionally.');
  }

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) {
    throw StateError('Guarded sync must never delete unconditionally.');
  }

  String _type(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtistRecord() => 'artist',
      CloudAlbumRecord() => 'album',
      CloudAlbumEditionRecord() => 'albumEdition',
      CloudSongRecord() => 'song',
      CloudArtworkAssetRecord() => 'artworkAsset',
      _ => 'unknown',
    };
  }
}

class _MemoryConflictRepository implements OutboundConflictRepository {
  final Map<String, OutboundSyncConflict> _values = {};

  Iterable<OutboundSyncConflict> get values => _values.values;

  String _key(String userId, CloudDataEntity type, String id) =>
      '$userId|${type.name}|$id';

  @override
  Future<void> record(OutboundSyncConflict conflict) async {
    _values[_key(conflict.userId, conflict.entityType, conflict.entityId)] =
        conflict;
  }

  @override
  Future<OutboundSyncConflict?> get({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    return _values[_key(userId, entityType, entityId)];
  }

  @override
  Future<List<OutboundSyncConflict>> getAll(String userId) async {
    return _values.values.where((value) => value.userId == userId).toList();
  }

  @override
  Future<void> clear({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    _values.remove(_key(userId, entityType, entityId));
  }

  @override
  Future<void> clearResolved({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required String outboxId,
    required int mutationRevision,
  }) async {
    final key = _key(userId, entityType, entityId);
    final current = _values[key];

    if (current != null &&
        !(current.outboxId == outboxId &&
            current.mutationRevision > mutationRevision)) {
      _values.remove(key);
    }
  }
}
