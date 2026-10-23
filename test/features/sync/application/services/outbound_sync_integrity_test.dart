import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
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
        outbox,
        song;

// SN-47 H3/D3 (revision-guarded writes) and D8 (outbox isolation).
void main() {
  final timestamp = DateTime.utc(2026, 10, 23, 12);

  late FakeLocalSyncRepository localSync;
  late FakeArtistRepository artists;
  late FakeAlbumRepository albums;
  late FakeAlbumEditionRepository editions;
  late FakeSongRepository songs;
  late FakeArtworkAssetRepository artworks;
  late FakeCloudArtworkStorage storage;
  late _ConditionalGateway gateway;
  late FakeCloudRevisionBaselineRepository baselines;

  setUp(() {
    localSync = FakeLocalSyncRepository();
    artists = FakeArtistRepository();
    albums = FakeAlbumRepository();
    editions = FakeAlbumEditionRepository();
    songs = FakeSongRepository();
    artworks = FakeArtworkAssetRepository();
    storage = FakeCloudArtworkStorage();
    gateway = _ConditionalGateway();
    baselines = FakeCloudRevisionBaselineRepository();
  });

  OutboundSyncProcessor legacyProcessor() {
    return OutboundSyncProcessor(
      localSyncRepository: localSync,
      artistRepository: artists,
      albumRepository: albums,
      albumEditionRepository: editions,
      songRepository: songs,
      metadataFieldStateRepository: FakeMetadataFieldStateRepository(),
      artworkAssetRepository: artworks,
      cloudArtworkStorage: storage,
      cloudSyncGateway: gateway,
    );
  }

  // Mirrors production composition: baselines plus guarded artists.
  OutboundSyncProcessor guardedProcessor() {
    return OutboundSyncProcessor(
      localSyncRepository: localSync,
      artistRepository: artists,
      albumRepository: albums,
      albumEditionRepository: editions,
      songRepository: songs,
      metadataFieldStateRepository: FakeMetadataFieldStateRepository(),
      artworkAssetRepository: artworks,
      cloudArtworkStorage: storage,
      cloudSyncGateway: gateway,
      cloudRevisionBaselineRepository: baselines,
      pushArtistMutation:
          ({required userId, required entry, required artist}) async {
            throw StateError('Unexpected explicit artist upload.');
          },
      ensureArtistDependency: ({required userId, required artist}) async {},
    );
  }

  void seedLibrary() {
    artists.values['artist_1'] = artist(timestamp);
    albums.values['album_1'] = album(timestamp);
    editions.values['edition_1'] = edition(timestamp);
    songs.values['song_1'] = song(timestamp);
    artworks.values['artwork_1'] = artwork(timestamp);
  }

  void seedBaseline(CloudDataEntity type, String id, int revision) {
    baselines.revisions['user_1:${type.name}:$id'] = revision;
  }

  int? baselineOf(CloudDataEntity type, String id) {
    return baselines.revisions['user_1:${type.name}:$id'];
  }

  group('D8 outbox isolation', () {
    test('one failing entry does not block later eligible entries', () async {
      artists.values['artist_1'] = artist(timestamp);
      albums.values['album_1'] = album(timestamp);
      albums.values['album_2'] = album(
        timestamp,
      ).copyWith(id: 'album_2', title: 'Second', canonicalTitle: 'second');

      localSync.pending.addAll([
        outbox(
          id: 'outbox_album_1',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_album_2',
          type: CloudDataEntity.album,
          entityId: 'album_2',
          timestamp: timestamp.add(const Duration(seconds: 1)),
        ),
      ]);

      gateway.failOn = 'upsert:album:album_1';

      await expectLater(
        legacyProcessor().pushPending('user_1'),
        throwsA(anything),
      );

      expect(gateway.calls, contains('upsert:album:album_2'));
      expect(localSync.processedIds, ['outbox_album_2']);
      expect(localSync.pending.map((entry) => entry.id), ['outbox_album_1']);
    });

    test('an entry depending on a failed entry stays pending', () async {
      seedLibrary();

      localSync.pending.addAll([
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
      ]);

      gateway.failOn = 'upsert:album:album_1';

      await expectLater(
        legacyProcessor().pushPending('user_1'),
        throwsA(anything),
      );

      // The song re-attempts its album dependency and fails before writing.
      expect(gateway.calls, isNot(contains('upsert:song:song_1')));
      expect(localSync.processedIds, isEmpty);
      expect(
        localSync.pending.map((entry) => entry.id),
        containsAll(['outbox_album', 'outbox_song']),
      );
    });

    test(
      'foreign ownership anywhere in the batch blocks every write',
      () async {
        seedLibrary();

        localSync.pending.addAll([
          outbox(
            id: 'outbox_artist',
            type: CloudDataEntity.artist,
            entityId: 'artist_1',
            timestamp: timestamp,
          ),
          SyncOutboxEntry(
            id: 'outbox_foreign',
            userId: 'user_2',
            entityType: CloudDataEntity.song,
            entityId: 'song_1',
            operation: SyncOutboxOperation.upsert,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ]);

        await expectLater(
          legacyProcessor().pushPending('user_1'),
          throwsStateError,
        );

        expect(gateway.calls, isEmpty);
        expect(localSync.processedIds, isEmpty);
      },
    );
  });

  group('H3 revision-guarded non-artist writes', () {
    test('explicit edit with a baseline is compare-and-set', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.album, 'album_1', 4);
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);

      localSync.pending.add(
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      await guardedProcessor().pushPending('user_1');

      expect(gateway.calls, ['update:album:album_1@4']);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 5);
      expect(localSync.processedIds, ['outbox_album']);
    });

    test('newer cloud revision is not overwritten', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.album, 'album_1', 4);
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);

      gateway.results['update:album:album_1@4'] =
          const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.conflict,
            serverRevision: 6,
          );

      localSync.pending.add(
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        guardedProcessor().pushPending('user_1'),
        throwsA(
          predicate(
            (error) => error.toString().contains('OutboundRecordWriteConflict'),
          ),
        ),
      );

      expect(gateway.calls, ['update:album:album_1@4']);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 4);
      expect(localSync.processedIds, isEmpty);
      expect(localSync.pending, hasLength(1));
    });

    test(
      'explicit edit without a baseline never replaces a cloud row',
      () async {
        seedLibrary();
        seedBaseline(CloudDataEntity.artist, 'artist_1', 2);

        gateway.results['insert:album:album_1'] =
            const CloudConditionalWriteResult(
              outcome: CloudConditionalWriteOutcome.conflict,
              serverRevision: 3,
            );

        localSync.pending.add(
          outbox(
            id: 'outbox_album',
            type: CloudDataEntity.album,
            entityId: 'album_1',
            timestamp: timestamp,
          ),
        );

        await expectLater(
          guardedProcessor().pushPending('user_1'),
          throwsA(anything),
        );

        expect(gateway.calls, ['insert:album:album_1']);
        expect(baselineOf(CloudDataEntity.album, 'album_1'), isNull);
        expect(localSync.pending, hasLength(1));
      },
    );

    test('new record is inserted at revision 1', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);

      localSync.pending.add(
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      await guardedProcessor().pushPending('user_1');

      expect(gateway.calls, ['insert:album:album_1']);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), 1);
      expect(localSync.processedIds, ['outbox_album']);
    });

    test('reconciled dependencies are not rewritten by a song push', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);
      seedBaseline(CloudDataEntity.album, 'album_1', 3);
      seedBaseline(CloudDataEntity.albumEdition, 'edition_1', 4);
      seedBaseline(CloudDataEntity.artworkAsset, 'artwork_1', 1);

      localSync.pending.add(
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
      );

      await guardedProcessor().pushPending('user_1');

      expect(storage.calls, isEmpty);
      expect(gateway.calls, ['insert:song:song_1']);
      expect(localSync.processedIds, ['outbox_song']);
    });

    test('existing unreconciled dependency is used, not overwritten', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);
      seedBaseline(CloudDataEntity.artworkAsset, 'artwork_1', 1);

      gateway.results['insert:album:album_1'] =
          const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.conflict,
            serverRevision: 7,
          );

      // The live cloud album differs from local content: it is used as a
      // dependency but never adopted as a baseline.
      gateway.currentRows['album:album_1'] = CloudSyncItem(
        record: CloudAlbumRecord(
          id: 'album_1',
          userId: 'user_1',
          artistId: 'artist_1',
          title: 'Cloud Title',
          canonicalTitle: 'cloud title',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        serverUpdatedAt: timestamp,
        serverRevision: 7,
      );

      localSync.pending.add(
        outbox(
          id: 'outbox_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
      );

      await guardedProcessor().pushPending('user_1');

      expect(gateway.calls, [
        'insert:album:album_1',
        'insert:albumEdition:edition_1',
      ]);
      expect(baselineOf(CloudDataEntity.album, 'album_1'), isNull);
      expect(baselineOf(CloudDataEntity.albumEdition, 'edition_1'), 1);
      expect(localSync.processedIds, ['outbox_edition']);
    });

    test('unexpected applied revision leaves the entry pending', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.album, 'album_1', 4);
      seedBaseline(CloudDataEntity.artist, 'artist_1', 2);

      gateway.results['update:album:album_1@4'] =
          const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.applied,
            serverRevision: 9,
          );

      localSync.pending.add(
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        guardedProcessor().pushPending('user_1'),
        throwsStateError,
      );

      expect(baselineOf(CloudDataEntity.album, 'album_1'), 4);
      expect(localSync.pending, hasLength(1));
    });

    test('explicit artwork edit is revision-guarded after upload', () async {
      seedLibrary();
      seedBaseline(CloudDataEntity.artworkAsset, 'artwork_1', 2);

      localSync.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );

      await guardedProcessor().pushPending('user_1');

      // One immutable key per mutation; nothing is overwritten.
      expect(storage.calls, [
        'uploadImmutable:user_1:artwork_1:outbox_artwork-r1',
      ]);
      expect(gateway.calls, ['update:artworkAsset:artwork_1@2']);
      expect(baselineOf(CloudDataEntity.artworkAsset, 'artwork_1'), 3);
    });
  });
}

/// Records every cloud write. Conditional writes succeed with the next
/// revision unless [results] overrides them.
///
class _ConditionalGateway implements CloudSyncGateway {
  final List<String> calls = [];
  final Map<String, CloudConditionalWriteResult> results = {};
  String? failOn;

  @override
  Future<void> upsert(CloudOwnedRecord record) async {
    _record('upsert:${_type(record)}:${record.id}');
  }

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(
    CloudOwnedRecord record,
  ) async {
    final call = 'insert:${_type(record)}:${record.id}';
    _record(call);

    return results[call] ??
        const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: 1,
        );
  }

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) async {
    final call = 'update:${_type(record)}:${record.id}@$expectedServerRevision';
    _record(call);

    return results[call] ??
        CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: expectedServerRevision + 1,
        );
  }

  /// Current cloud rows keyed by `type:id`; absent rows return null.
  final Map<String, CloudSyncItem> currentRows = {};
  int fetchCount = 0;

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    fetchCount += 1;
    final item = currentRows['${entityType.name}:$entityId'];

    // Row-level security never returns another account's row.
    return item == null || item.record.userId != userId ? null : item;
  }

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) async {
    final call =
        'conditionalDelete:${entityType.name}:$entityId@$expectedServerRevision';
    _record(call);

    return results[call] ??
        CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: expectedServerRevision + 1,
        );
  }

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) async {
    _record('delete:${entityType.name}:$entityId');
  }

  void _record(String call) {
    calls.add(call);

    if (call == failOn) {
      throw StateError('Simulated cloud failure: $call');
    }
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
