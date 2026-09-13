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
import 'package:sonus_next/features/sync/application/services/inbound_cloud_record_applier.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_context.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  const applier = InboundCloudRecordApplier();

  group('InboundCloudRecordApplier', () {
    test('creates artist when it does not exist locally', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.artist, {
        'id': 'artist-1',
        'user_id': 'user-1',
        'name': 'Artist Name',
        'canonical_name': 'artist name',
        'header_artwork_id': null,
        'top_artists_artwork_id': null,
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      expect(bundle.artist.created, isNotNull);
      expect(bundle.artist.saved, isNull);
      expect(bundle.artist.created?.id, 'artist-1');
      expect(bundle.artist.created?.name, 'Artist Name');
      expect(bundle.artist.created?.canonicalName, 'artist name');
    });

    test('saves artist when it already exists locally', () async {
      final bundle = _TestContextBundle();

      bundle.artist.existing = Artist(
        id: 'artist-1',
        name: 'Old Name',
        canonicalName: 'old name',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final record = _recordFromRow(CloudDataEntity.artist, {
        'id': 'artist-1',
        'user_id': 'user-1',
        'name': 'New Name',
        'canonical_name': 'new name',
        'header_artwork_id': 'header-1',
        'top_artists_artwork_id': 'top-1',
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      expect(bundle.artist.created, isNull);
      expect(bundle.artist.saved, isNotNull);
      expect(bundle.artist.saved?.name, 'New Name');
      expect(bundle.artist.saved?.headerArtworkId, 'header-1');
      expect(bundle.artist.saved?.topArtistsArtworkId, 'top-1');
    });

    test('maps and creates album', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.album, {
        'id': 'album-1',
        'user_id': 'user-1',
        'artist_id': 'artist-1',
        'title': 'Album Title',
        'canonical_title': 'album title',
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      expect(bundle.album.created, isNotNull);
      expect(bundle.album.created?.id, 'album-1');
      expect(bundle.album.created?.artistId, 'artist-1');
      expect(bundle.album.created?.title, 'Album Title');
    });

    test('maps album edition type and nullable metadata', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.albumEdition, {
        'id': 'edition-1',
        'user_id': 'user-1',
        'album_id': 'album-1',
        'title': 'Deluxe Edition',
        'type': 'deluxe',
        'is_primary': false,
        'release_date': '2026-08-01T00:00:00.000Z',
        'genre': 'Pop',
        'artwork_id': 'artwork-1',
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      final edition = bundle.edition.created;

      expect(edition, isNotNull);
      expect(edition?.type, AlbumEditionType.deluxe);
      expect(edition?.genre, 'Pop');
      expect(edition?.artworkId, 'artwork-1');
      expect(
        edition?.releaseDate,
        DateTime.parse('2026-08-01T00:00:00.000Z').toUtc(),
      );
    });

    test('maps song fields including featured artists', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.song, {
        'id': 'song-1',
        'user_id': 'user-1',
        'artist_id': 'artist-1',
        'album_id': 'album-1',
        'album_edition_id': 'edition-1',
        'title': 'Song Title',
        'canonical_title': 'song title',
        'track_number': 7,
        'duration_seconds': 222,
        'is_single': true,
        'featured_artists': ['Feature One', 'Feature Two'],
        'artwork_id': null,
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      final song = bundle.song.created;

      expect(song, isNotNull);
      expect(song?.trackNumber, 7);
      expect(song?.durationSeconds, 222);
      expect(song?.isSingle, isTrue);
      expect(song?.featuredArtists, ['Feature One', 'Feature Two']);
    });

    test('rejects tombstones without mutating local data', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.artist, {
        'id': 'artist-1',
        'user_id': 'user-1',
        'name': 'Artist',
        'canonical_name': 'artist',
        'header_artwork_id': null,
        'top_artists_artwork_id': null,
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-12T12:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:01.000Z',
        'deleted_at': '2026-09-12T12:00:00.000Z',
      });

      await expectLater(
        applier.apply(record: record, context: bundle.context),
        throwsStateError,
      );

      expect(bundle.artist.created, isNull);
      expect(bundle.artist.saved, isNull);
    });

    test('rejects artwork until Storage download is implemented', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.artworkAsset, {
        'id': 'artwork-1',
        'user_id': 'user-1',
        'storage_object_key': 'user-1/artwork-1.jpg',
        'created_at': '2026-09-10T10:00:00.000Z',
        'updated_at': '2026-09-11T11:00:00.000Z',
        'server_updated_at': '2026-09-12T12:00:00.000Z',
        'deleted_at': null,
      });

      await expectLater(
        applier.apply(record: record, context: bundle.context),
        throwsStateError,
      );

      expect(bundle.artwork.created, isNull);
      expect(bundle.artwork.saved, isNull);
    });
  });
}

CloudOwnedRecord _recordFromRow(
  CloudDataEntity entityType,
  Map<String, dynamic> row,
) {
  return SupabaseCloudRecordMapper.fromRow(
    entityType: entityType,
    row: row,
  ).record;
}

class _TestContextBundle {
  _TestContextBundle()
    : artist = _FakeArtistRepository(),
      album = _FakeAlbumRepository(),
      edition = _FakeAlbumEditionRepository(),
      song = _FakeSongRepository(),
      artwork = _FakeArtworkRepository(),
      localSync = _FakeLocalSyncRepository() {
    context = SyncMutationContext(
      artistRepository: artist,
      albumRepository: album,
      albumEditionRepository: edition,
      songRepository: song,
      artworkAssetRepository: artwork,
      localSyncRepository: localSync,
    );
  }

  final _FakeArtistRepository artist;
  final _FakeAlbumRepository album;
  final _FakeAlbumEditionRepository edition;
  final _FakeSongRepository song;
  final _FakeArtworkRepository artwork;
  final _FakeLocalSyncRepository localSync;

  late final SyncMutationContext context;
}

class _FakeArtistRepository implements ArtistRepository {
  Artist? existing;
  Artist? created;
  Artist? saved;

  @override
  Future<Artist?> getById(String id) async => existing;

  @override
  Future<void> create(Artist artist) async {
    created = artist;
  }

  @override
  Future<void> save(Artist artist) async {
    saved = artist;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlbumRepository implements AlbumRepository {
  Album? existing;
  Album? created;
  Album? saved;

  @override
  Future<Album?> getById(String id) async => existing;

  @override
  Future<void> create(Album album) async {
    created = album;
  }

  @override
  Future<void> save(Album album) async {
    saved = album;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlbumEditionRepository implements AlbumEditionRepository {
  AlbumEdition? existing;
  AlbumEdition? created;
  AlbumEdition? saved;

  @override
  Future<AlbumEdition?> getById(String id) async => existing;

  @override
  Future<void> create(AlbumEdition edition) async {
    created = edition;
  }

  @override
  Future<void> save(AlbumEdition edition) async {
    saved = edition;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSongRepository implements SongRepository {
  Song? existing;
  Song? created;
  Song? saved;

  @override
  Future<Song?> getById(String id) async => existing;

  @override
  Future<void> create(Song song) async {
    created = song;
  }

  @override
  Future<void> save(Song song) async {
    saved = song;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArtworkRepository implements ArtworkAssetRepository {
  ArtworkAsset? created;
  ArtworkAsset? saved;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalSyncRepository implements LocalSyncRepository {
  @override
  Future<SyncCursor?> getCursor(
    String userId,
    CloudDataEntity entityType,
  ) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
