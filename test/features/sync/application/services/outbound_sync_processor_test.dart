import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/sync/application/repositories/local_sync_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artwork_storage.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  group('OutboundSyncProcessor', () {
    late FakeLocalSyncRepository localSyncRepository;
    late FakeArtistRepository artistRepository;
    late FakeAlbumRepository albumRepository;
    late FakeAlbumEditionRepository albumEditionRepository;
    late FakeSongRepository songRepository;
    late FakeArtworkAssetRepository artworkAssetRepository;
    late FakeCloudArtworkStorage cloudArtworkStorage;
    late FakeCloudSyncGateway cloudSyncGateway;
    late OutboundSyncProcessor processor;

    final timestamp = DateTime.utc(2026, 9, 13, 12);

    setUp(() {
      localSyncRepository = FakeLocalSyncRepository();
      artistRepository = FakeArtistRepository();
      albumRepository = FakeAlbumRepository();
      albumEditionRepository = FakeAlbumEditionRepository();
      songRepository = FakeSongRepository();
      artworkAssetRepository = FakeArtworkAssetRepository();
      cloudArtworkStorage = FakeCloudArtworkStorage();
      cloudSyncGateway = FakeCloudSyncGateway();

      processor = OutboundSyncProcessor(
        localSyncRepository: localSyncRepository,
        artistRepository: artistRepository,
        albumRepository: albumRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
        artworkAssetRepository: artworkAssetRepository,
        cloudArtworkStorage: cloudArtworkStorage,
        cloudSyncGateway: cloudSyncGateway,
      );
    });

    test('does nothing when outbox is empty', () async {
      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });

    test('pushes related upserts in dependency order', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);
      albumEditionRepository.values['edition_1'] = edition(timestamp);
      songRepository.values['song_1'] = song(timestamp);

      localSyncRepository.pending.addAll([
        outbox(
          id: 'a_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'b_edition',
          type: CloudDataEntity.albumEdition,
          entityId: 'edition_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'c_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'd_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'z_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      ]);

      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);

      expect(cloudSyncGateway.calls, [
        'upsert:artworkAsset:artwork_1',
        'upsert:artist:artist_1',
        'upsert:album:album_1',
        'upsert:albumEdition:edition_1',
        'upsert:song:song_1',
      ]);

      expect(localSyncRepository.processedIds, [
        'd_artwork',
        'z_artist',
        'c_album',
        'b_edition',
        'a_song',
      ]);
    });

    test('successful artwork upload writes returned storage key', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      cloudArtworkStorage.returnedObjectKey = 'user_1/artwork_1.png';

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);

      expect(cloudSyncGateway.calls, ['upsert:artworkAsset:artwork_1']);

      final record = cloudSyncGateway.upsertedRecords.single;
      expect(record, isA<CloudArtworkAssetRecord>());

      final artworkRecord = record as CloudArtworkAssetRecord;
      expect(artworkRecord.storageObjectKey, 'user_1/artwork_1.png');

      expect(localSyncRepository.processedIds, ['outbox_artwork']);
    });

    test('artwork storage failure leaves entry pending', () async {
      artworkAssetRepository.values['artwork_1'] = artwork(timestamp);
      cloudArtworkStorage.shouldFail = true;

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'artwork_1',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test(
      'artwork database failure leaves entry pending after upload',
      () async {
        artworkAssetRepository.values['artwork_1'] = artwork(timestamp);

        localSyncRepository.pending.add(
          outbox(
            id: 'outbox_artwork',
            type: CloudDataEntity.artworkAsset,
            entityId: 'artwork_1',
            timestamp: timestamp,
          ),
        );

        cloudSyncGateway.failOn = 'upsert:artworkAsset:artwork_1';

        await expectLater(
          processor.pushPending('user_1'),
          throwsA(isA<StateError>()),
        );

        expect(cloudArtworkStorage.calls, ['upload:user_1:artwork_1']);
        expect(cloudSyncGateway.calls, ['upsert:artworkAsset:artwork_1']);
        expect(localSyncRepository.processedIds, isEmpty);
        expect(localSyncRepository.pending, hasLength(1));
      },
    );

    test('missing local artwork leaves upsert pending', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artwork',
          type: CloudDataEntity.artworkAsset,
          entityId: 'missing_artwork',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudArtworkStorage.calls, isEmpty);
      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test('acknowledges an entry only after cloud success', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, ['upsert:artist:artist_1']);
      expect(localSyncRepository.processedIds, ['outbox_artist']);
    });

    test('cloud failure leaves failed and later entries pending', () async {
      artistRepository.values['artist_1'] = artist(timestamp);
      albumRepository.values['album_1'] = album(timestamp);
      songRepository.values['song_1'] = song(timestamp);

      localSyncRepository.pending.addAll([
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'song_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_album',
          type: CloudDataEntity.album,
          entityId: 'album_1',
          timestamp: timestamp,
        ),
        outbox(
          id: 'outbox_artist',
          type: CloudDataEntity.artist,
          entityId: 'artist_1',
          timestamp: timestamp,
        ),
      ]);

      cloudSyncGateway.failOn = 'upsert:album:album_1';

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudSyncGateway.calls, [
        'upsert:artist:artist_1',
        'upsert:album:album_1',
      ]);

      expect(localSyncRepository.processedIds, ['outbox_artist']);
      expect(
        localSyncRepository.pending.map((entry) => entry.id),
        containsAll(['outbox_album', 'outbox_song']),
      );
    });

    test('missing local entity leaves upsert pending', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_song',
          type: CloudDataEntity.song,
          entityId: 'missing_song',
          timestamp: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
      expect(localSyncRepository.pending, hasLength(1));
    });

    test('delete does not require local entity and is acknowledged', () async {
      localSyncRepository.pending.add(
        outbox(
          id: 'outbox_delete',
          type: CloudDataEntity.song,
          entityId: 'deleted_song',
          timestamp: timestamp,
          operation: SyncOutboxOperation.delete,
        ),
      );

      await processor.pushPending('user_1');

      expect(cloudSyncGateway.calls, [
        'delete:song:deleted_song:${timestamp.toIso8601String()}',
      ]);
      expect(localSyncRepository.processedIds, ['outbox_delete']);
    });

    test('rejects blank user id', () async {
      await expectLater(
        processor.pushPending('   '),
        throwsA(isA<ArgumentError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
    });

    test('rejects an outbox entry belonging to another user', () async {
      artistRepository.values['artist_1'] = artist(timestamp);

      localSyncRepository.pending.add(
        SyncOutboxEntry(
          id: 'wrong_user_entry',
          userId: 'user_2',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          operation: SyncOutboxOperation.upsert,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );

      await expectLater(
        processor.pushPending('user_1'),
        throwsA(isA<StateError>()),
      );

      expect(cloudSyncGateway.calls, isEmpty);
      expect(localSyncRepository.processedIds, isEmpty);
    });
  });
}

SyncOutboxEntry outbox({
  required String id,
  required CloudDataEntity type,
  required String entityId,
  required DateTime timestamp,
  SyncOutboxOperation operation = SyncOutboxOperation.upsert,
}) {
  return SyncOutboxEntry(
    id: id,
    userId: 'user_1',
    entityType: type,
    entityId: entityId,
    operation: operation,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

ArtworkAsset artwork(DateTime timestamp) {
  return ArtworkAsset(
    id: 'artwork_1',
    filePath: r'C:\artwork\artwork_1.png',
    normalizedPath: r'c:\artwork\artwork_1.png',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Artist artist(DateTime timestamp) {
  return Artist(
    id: 'artist_1',
    name: 'Artist',
    canonicalName: 'artist',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Album album(DateTime timestamp) {
  return Album(
    id: 'album_1',
    artistId: 'artist_1',
    title: 'Album',
    canonicalTitle: 'album',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

AlbumEdition edition(DateTime timestamp) {
  return AlbumEdition(
    id: 'edition_1',
    albumId: 'album_1',
    title: 'Standard',
    type: AlbumEditionType.standard,
    isPrimary: true,
    artworkId: 'artwork_1',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Song song(DateTime timestamp) {
  return Song(
    id: 'song_1',
    artistId: 'artist_1',
    albumId: 'album_1',
    albumEditionId: 'edition_1',
    title: 'Song',
    canonicalTitle: 'song',
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    artworkId: 'artwork_1',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class FakeLocalSyncRepository implements LocalSyncRepository {
  final List<SyncOutboxEntry> pending = [];
  final List<String> processedIds = [];

  @override
  Future<List<SyncOutboxEntry>> getPending(String userId) async {
    return List.unmodifiable(pending);
  }

  @override
  Future<void> markProcessed({
    required String userId,
    required String outboxEntryId,
  }) async {
    processedIds.add(outboxEntryId);
    pending.removeWhere(
      (entry) => entry.userId == userId && entry.id == outboxEntryId,
    );
  }

  @override
  Future<SyncCursor?> getCursor(
    String userId,
    CloudDataEntity entityType,
  ) async {
    return null;
  }

  @override
  Future<void> saveCursor(SyncCursor cursor) async {}

  @override
  Future<void> recordUpsert({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {}

  @override
  Future<void> recordDelete({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {}
}

class FakeCloudArtworkStorage implements CloudArtworkStorage {
  final List<String> calls = [];
  bool shouldFail = false;
  String returnedObjectKey = 'user_1/artwork_1.png';

  @override
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  }) async {
    final call = 'upload:$userId:${artworkAsset.id}';
    calls.add(call);

    if (shouldFail) {
      throw StateError('Simulated artwork storage failure.');
    }

    return returnedObjectKey;
  }
}

class FakeCloudSyncGateway implements CloudSyncGateway {
  final List<String> calls = [];
  final List<CloudOwnedRecord> upsertedRecords = [];
  String? failOn;

  @override
  Future<void> upsert(CloudOwnedRecord record) async {
    final type = switch (record) {
      CloudArtistRecord() => 'artist',
      CloudAlbumRecord() => 'album',
      CloudAlbumEditionRecord() => 'albumEdition',
      CloudSongRecord() => 'song',
      CloudArtworkAssetRecord() => 'artworkAsset',
      _ => 'unknown',
    };

    final call = 'upsert:$type:${record.id}';
    calls.add(call);
    upsertedRecords.add(record);

    if (call == failOn) {
      throw StateError('Simulated cloud failure.');
    }
  }

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) async {
    final call =
        'delete:${entityType.name}:$entityId:${deletedAt.toIso8601String()}';
    calls.add(call);

    if (call == failOn) {
      throw StateError('Simulated cloud failure.');
    }
  }
}

class FakeArtistRepository implements ArtistRepository {
  final Map<String, Artist> values = {};

  @override
  Future<Artist?> getById(String id) async => values[id];

  @override
  Future<void> create(Artist artist) async {
    values[artist.id] = artist;
  }

  @override
  Future<void> save(Artist artist) async {
    values[artist.id] = artist;
  }

  @override
  Future<List<Artist>> getAll() async => values.values.toList();
}

class FakeAlbumRepository implements AlbumRepository {
  final Map<String, Album> values = {};

  @override
  Future<Album?> getById(String id) async => values[id];

  @override
  Future<void> create(Album album) async {
    values[album.id] = album;
  }

  @override
  Future<void> save(Album album) async {
    values[album.id] = album;
  }

  @override
  Future<List<Album>> getAll() async => values.values.toList();

  @override
  Future<List<Album>> getByArtistId(String artistId) async {
    return values.values.where((album) => album.artistId == artistId).toList();
  }

  @override
  Future<List<Album>> getRecentlyAdded(int limit) async {
    return values.values.take(limit).toList();
  }
}

class FakeAlbumEditionRepository implements AlbumEditionRepository {
  final Map<String, AlbumEdition> values = {};

  @override
  Future<AlbumEdition?> getById(String id) async => values[id];

  @override
  Future<void> create(AlbumEdition edition) async {
    values[edition.id] = edition;
  }

  @override
  Future<void> save(AlbumEdition edition) async {
    values[edition.id] = edition;
  }

  @override
  Future<List<AlbumEdition>> getAll() async => values.values.toList();

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async {
    return values.values
        .where((edition) => edition.albumId == albumId)
        .toList();
  }
}

class FakeSongRepository implements SongRepository {
  final Map<String, Song> values = {};

  @override
  Future<Song?> getById(String id) async => values[id];

  @override
  Future<void> create(Song song) async {
    values[song.id] = song;
  }

  @override
  Future<void> save(Song song) async {
    values[song.id] = song;
  }

  @override
  Future<List<Song>> getAll() async => values.values.toList();

  @override
  Future<List<Song>> getByArtistId(String artistId) async {
    return values.values.where((song) => song.artistId == artistId).toList();
  }

  @override
  Future<List<Song>> getByAlbumId(String albumId) async {
    return values.values.where((song) => song.albumId == albumId).toList();
  }

  @override
  Future<List<Song>> getByEditionId(String editionId) async {
    return values.values
        .where((song) => song.albumEditionId == editionId)
        .toList();
  }

  @override
  Future<List<Song>> getRecentlyAdded(int limit) async {
    return values.values.take(limit).toList();
  }
}

class FakeArtworkAssetRepository implements ArtworkAssetRepository {
  final Map<String, ArtworkAsset> values = {};

  @override
  Future<ArtworkAsset?> getById(String id) async => values[id];

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) async {
    for (final value in values.values) {
      if (value.normalizedPath == normalizedPath) {
        return value;
      }
    }

    return null;
  }

  @override
  Future<void> create(ArtworkAsset artworkAsset) async {
    values[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) async {
    values[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<List<ArtworkAsset>> getAll() async => values.values.toList();
}
