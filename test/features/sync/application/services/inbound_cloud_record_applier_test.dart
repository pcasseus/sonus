import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_track_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_artist_credit_repository.dart';
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
        'is_blacklisted': true,
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
        'is_blacklisted': false,
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
        'disc_number': 2,
        'duration_seconds': 222,
        'is_single': true,
        'is_blocked': true,
        'featured_artists': ['Feature One', 'Feature Two'],
        'version_label': 'Festival Mix',
        'version_characteristics': ['live', 'remix'],
        'release_status': 'unreleased',
        'is_leak': true,
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
      expect(song?.discNumber, 2);
      expect(song?.durationSeconds, 222);
      expect(song?.isSingle, isTrue);
      expect(song?.isBlocked, isTrue);
      expect(song?.featuredArtists, ['Feature One', 'Feature Two']);
      expect(song?.versionLabel, 'Festival Mix');
      expect(song?.versionCharacteristics, const [
        SongVersionCharacteristic.live,
        SongVersionCharacteristic.remix,
      ]);
      expect(song?.releaseStatus, SongReleaseStatus.unreleased);
      expect(song?.isLeak, isTrue);
      final createdMembership = bundle.membership.created;

      expect(createdMembership, isNotNull);
      expect(createdMembership?.albumEditionId, 'edition-1');
      expect(createdMembership?.songId, 'song-1');
      expect(createdMembership?.discNumber, 2);
      expect(createdMembership?.trackNumber, 7);
      expect(createdMembership?.sortPosition, 0);
      expect(
        createdMembership?.createdAt,
        DateTime.parse('2026-09-10T10:00:00.000Z').toUtc(),
      );
      expect(
        createdMembership?.updatedAt,
        DateTime.parse('2026-09-11T11:00:00.000Z').toUtc(),
      );
    });

    test(
      'inbound song updates compatibility placement without changing sort position',
      () async {
        final bundle = _TestContextBundle();

        bundle.song.existing = Song(
          id: 'song-1',
          artistId: 'artist-1',
          albumId: 'album-1',
          albumEditionId: 'edition-1',
          title: 'Old Song',
          canonicalTitle: 'old song',
          trackNumber: 1,
          discNumber: 1,
          durationSeconds: 200,
          isSingle: false,
          isBlocked: false,
          featuredArtists: const [],
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

        bundle.membership.memberships.add(
          AlbumEditionTrack(
            albumEditionId: 'edition-1',
            songId: 'song-1',
            discNumber: 1,
            trackNumber: 1,
            sortPosition: 9,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final record = _recordFromRow(CloudDataEntity.song, {
          'id': 'song-1',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'edition-1',
          'title': 'Cloud Song',
          'canonical_title': 'cloud song',
          'track_number': 8,
          'disc_number': 2,
          'duration_seconds': 220,
          'is_single': false,
          'is_blocked': false,
          'featured_artists': <String>[],
          'artwork_id': null,
          'created_at': '2026-09-01T00:00:00.000Z',
          'updated_at': '2026-09-20T00:00:00.000Z',
          'server_updated_at': '2026-09-20T00:00:01.000Z',
          'deleted_at': null,
        });

        await applier.apply(record: record, context: bundle.context);

        final membership = bundle.membership.memberships.single;

        expect(membership.albumEditionId, 'edition-1');
        expect(membership.discNumber, 2);
        expect(membership.trackNumber, 8);
        expect(membership.sortPosition, 9);
        expect(
          membership.numberingAuthority,
          AlbumEditionTrackAuthority.inferred,
        );
        expect(
          membership.orderingAuthority,
          AlbumEditionTrackAuthority.inferred,
        );
        expect(membership.createdAt, DateTime.utc(2026, 9, 1));
        expect(membership.updatedAt, DateTime.utc(2026, 9, 20));
      },
    );
    test('inbound song preserves manual compatibility numbering', () async {
      final bundle = _TestContextBundle();

      bundle.song.existing = Song(
        id: 'song-manual',
        artistId: 'artist-1',
        albumId: 'album-1',
        albumEditionId: 'edition-1',
        title: 'Local Song',
        canonicalTitle: 'local song',
        trackNumber: 9,
        discNumber: 2,
        durationSeconds: 200,
        isSingle: false,
        isBlocked: false,
        featuredArtists: const [],
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      bundle.membership.memberships.add(
        AlbumEditionTrack(
          albumEditionId: 'edition-1',
          songId: 'song-manual',
          discNumber: 2,
          trackNumber: 9,
          sortPosition: 6,
          numberingAuthority: AlbumEditionTrackAuthority.manual,
          orderingAuthority: AlbumEditionTrackAuthority.manual,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );

      final record = _recordFromRow(CloudDataEntity.song, {
        'id': 'song-manual',
        'user_id': 'user-1',
        'artist_id': 'artist-1',
        'album_id': 'album-1',
        'album_edition_id': 'edition-1',
        'title': 'Cloud Song',
        'canonical_title': 'cloud song',
        'track_number': 3,
        'disc_number': 1,
        'duration_seconds': 225,
        'is_single': false,
        'is_blocked': false,
        'featured_artists': <String>[],
        'artwork_id': null,
        'created_at': '2026-09-01T00:00:00.000Z',
        'updated_at': '2026-09-20T00:00:00.000Z',
        'server_updated_at': '2026-09-20T00:00:01.000Z',
        'deleted_at': null,
      });

      await applier.apply(record: record, context: bundle.context);

      final savedSong = bundle.song.saved;

      expect(savedSong, isNotNull);
      expect(savedSong!.title, 'Cloud Song');
      expect(savedSong.durationSeconds, 225);

      // Manual membership numbering remains the compatibility projection.
      expect(savedSong.discNumber, 2);
      expect(savedSong.trackNumber, 9);

      final membership = bundle.membership.memberships.single;

      expect(membership.discNumber, 2);
      expect(membership.trackNumber, 9);
      expect(membership.sortPosition, 6);
      expect(membership.numberingAuthority, AlbumEditionTrackAuthority.manual);
      expect(membership.orderingAuthority, AlbumEditionTrackAuthority.manual);
      expect(membership.createdAt, DateTime.utc(2026, 9, 1));
      expect(membership.updatedAt, DateTime.utc(2026, 9, 10));

      // No membership rewrite occurred.
      expect(bundle.membership.saved, isNull);
    });

    test(
      'same-album inbound edition change preserves prior membership',
      () async {
        final bundle = _TestContextBundle();

        bundle.song.existing = Song(
          id: 'song-1',
          artistId: 'artist-1',
          albumId: 'album-1',
          albumEditionId: 'standard-1',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 1,
          discNumber: 1,
          durationSeconds: 200,
          isSingle: false,
          isBlocked: false,
          featuredArtists: const [],
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

        bundle.membership.memberships.add(
          AlbumEditionTrack(
            albumEditionId: 'standard-1',
            songId: 'song-1',
            discNumber: 1,
            trackNumber: 1,
            sortPosition: 4,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final record = _recordFromRow(CloudDataEntity.song, {
          'id': 'song-1',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'deluxe-1',
          'title': 'Song',
          'canonical_title': 'song',
          'track_number': 5,
          'disc_number': 1,
          'duration_seconds': 200,
          'is_single': false,
          'is_blocked': false,
          'featured_artists': <String>[],
          'artwork_id': null,
          'created_at': '2026-09-01T00:00:00.000Z',
          'updated_at': '2026-09-20T00:00:00.000Z',
          'server_updated_at': '2026-09-20T00:00:01.000Z',
          'deleted_at': null,
        });

        await applier.apply(record: record, context: bundle.context);

        expect(bundle.membership.memberships, hasLength(2));

        final standard = bundle.membership.memberships.singleWhere(
          (membership) => membership.albumEditionId == 'standard-1',
        );
        final deluxe = bundle.membership.memberships.singleWhere(
          (membership) => membership.albumEditionId == 'deluxe-1',
        );

        expect(standard.sortPosition, 4);
        expect(standard.updatedAt, DateTime.utc(2026, 9, 1));

        expect(deluxe.discNumber, 1);
        expect(deluxe.trackNumber, 5);
        expect(deluxe.sortPosition, 0);

        expect(bundle.membership.deletedEditionId, isNull);
      },
    );

    test(
      'cross-album inbound move removes only former compatibility membership',
      () async {
        final bundle = _TestContextBundle();

        bundle.song.existing = Song(
          id: 'song-1',
          artistId: 'artist-1',
          albumId: 'old-album',
          albumEditionId: 'old-standard',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 1,
          discNumber: 1,
          durationSeconds: 200,
          isSingle: false,
          isBlocked: false,
          featuredArtists: const [],
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

        bundle.membership.memberships.addAll([
          AlbumEditionTrack(
            albumEditionId: 'old-standard',
            songId: 'song-1',
            discNumber: 1,
            trackNumber: 1,
            sortPosition: 3,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
          AlbumEditionTrack(
            albumEditionId: 'unrelated-local-edition',
            songId: 'song-1',
            discNumber: 1,
            trackNumber: 9,
            sortPosition: 12,
            createdAt: DateTime.utc(2026, 9, 2),
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
        ]);

        final record = _recordFromRow(CloudDataEntity.song, {
          'id': 'song-1',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'album_id': 'new-album',
          'album_edition_id': 'new-standard',
          'title': 'Song',
          'canonical_title': 'song',
          'track_number': 2,
          'disc_number': 1,
          'duration_seconds': 200,
          'is_single': false,
          'is_blocked': false,
          'featured_artists': <String>[],
          'artwork_id': null,
          'created_at': '2026-09-01T00:00:00.000Z',
          'updated_at': '2026-09-20T00:00:00.000Z',
          'server_updated_at': '2026-09-20T00:00:01.000Z',
          'deleted_at': null,
        });

        await applier.apply(record: record, context: bundle.context);

        expect(
          bundle.membership.memberships.any(
            (membership) => membership.albumEditionId == 'old-standard',
          ),
          isFalse,
        );

        expect(
          bundle.membership.memberships.any(
            (membership) =>
                membership.albumEditionId == 'unrelated-local-edition',
          ),
          isTrue,
        );

        final target = bundle.membership.memberships.singleWhere(
          (membership) => membership.albumEditionId == 'new-standard',
        );

        expect(target.songId, 'song-1');
        expect(target.trackNumber, 2);
        expect(target.sortPosition, 0);

        expect(bundle.membership.deletedEditionId, 'old-standard');
        expect(bundle.membership.deletedSongId, 'song-1');
      },
    );
    test('rejects tombstones without mutating local data', () async {
      final bundle = _TestContextBundle();

      final record = _recordFromRow(CloudDataEntity.artist, {
        'id': 'artist-1',
        'user_id': 'user-1',
        'name': 'Artist',
        'canonical_name': 'artist',
        'is_blacklisted': false,
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
      membership = _FakeAlbumEditionTrackRepository(),
      song = _FakeSongRepository(),
      credit = _FakeSongArtistCreditRepository(),
      artwork = _FakeArtworkRepository(),
      localSync = _FakeLocalSyncRepository() {
    context = SyncMutationContext(
      artistRepository: artist,
      albumRepository: album,
      albumEditionRepository: edition,
      albumEditionTrackRepository: membership,
      songRepository: song,
      songArtistCreditRepository: credit,
      artworkAssetRepository: artwork,
      localSyncRepository: localSync,
    );
  }

  final _FakeArtistRepository artist;
  final _FakeAlbumRepository album;
  final _FakeAlbumEditionRepository edition;
  final _FakeAlbumEditionTrackRepository membership;
  final _FakeSongRepository song;
  final _FakeSongArtistCreditRepository credit;
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

class _FakeAlbumEditionTrackRepository implements AlbumEditionTrackRepository {
  final List<AlbumEditionTrack> memberships = <AlbumEditionTrack>[];

  AlbumEditionTrack? created;
  AlbumEditionTrack? saved;
  String? deletedEditionId;
  String? deletedSongId;

  @override
  Future<void> create(AlbumEditionTrack membership) async {
    created = membership;
    memberships.add(membership);
  }

  @override
  Future<void> save(AlbumEditionTrack membership) async {
    saved = membership;

    final index = memberships.indexWhere((existing) => existing == membership);

    if (index < 0) {
      throw StateError('Membership not found.');
    }

    memberships[index] = membership;
  }

  @override
  Future<List<AlbumEditionTrack>> getByEditionId(String editionId) async {
    return [
      for (final membership in memberships)
        if (membership.albumEditionId == editionId) membership,
    ];
  }

  @override
  Future<List<AlbumEditionTrack>> getBySongId(String songId) async {
    return [
      for (final membership in memberships)
        if (membership.songId == songId) membership,
    ];
  }

  @override
  Future<void> delete({
    required String editionId,
    required String songId,
  }) async {
    deletedEditionId = editionId;
    deletedSongId = songId;

    memberships.removeWhere(
      (membership) =>
          membership.albumEditionId == editionId && membership.songId == songId,
    );
  }
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

class _FakeSongArtistCreditRepository implements SongArtistCreditRepository {
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
