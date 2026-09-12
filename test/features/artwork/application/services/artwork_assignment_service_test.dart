import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';

void main() {
  group('ArtworkAssignmentService.resolveArtworkAsset', () {
    test('creates artwork asset when normalized path does not exist', () async {
      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(artworkRepository: artworkRepository);

      final now = DateTime.utc(2026, 9, 12, 7);

      final result = await service.resolveArtworkAsset(
        filePath: r'  C:\Music\Artwork\Cover.JPG  ',
        now: now,
      );

      expect(result.id, startsWith('artwork_'));
      expect(result.filePath, r'C:\Music\Artwork\Cover.JPG');
      expect(result.normalizedPath, 'c:/music/artwork/cover.jpg');
      expect(result.createdAt, now);
      expect(result.updatedAt, now);

      expect(artworkRepository.createdAssets, hasLength(1));
      expect(artworkRepository.createdAssets.single, result);
    });

    test(
      'reuses existing artwork asset for equivalent normalized path',
      () async {
        final existing = ArtworkAsset(
          id: 'artwork_existing',
          filePath: r'C:\Music\Artwork\Cover.jpg',
          normalizedPath: 'c:/music/artwork/cover.jpg',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        final artworkRepository = _FakeArtworkAssetRepository(
          assets: [existing],
        );

        final service = _service(artworkRepository: artworkRepository);

        final result = await service.resolveArtworkAsset(
          filePath: r'c:\music\artwork\COVER.JPG',
        );

        expect(result, same(existing));
        expect(artworkRepository.createdAssets, isEmpty);
      },
    );

    test('rejects blank path before repository mutation', () async {
      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(artworkRepository: artworkRepository);

      await expectLater(
        () => service.resolveArtworkAsset(filePath: '   '),
        throwsA(isA<ArgumentError>()),
      );

      expect(artworkRepository.createdAssets, isEmpty);
      expect(artworkRepository.normalizedPathLookups, isEmpty);
    });
  });

  group('ArtworkAssignmentService artist artwork', () {
    test('assigns header artwork and updates artist timestamp', () async {
      final original = _artist();

      final artistRepository = _FakeArtistRepository(artists: [original]);

      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(
        artworkRepository: artworkRepository,
        artistRepository: artistRepository,
      );

      final now = DateTime.utc(2026, 9, 12, 8);

      final artwork = await service.assignArtistHeader(
        artistId: original.id,
        filePath: r'C:\Artwork\Artist Header.JPG',
        now: now,
      );

      final saved = artistRepository.artists[original.id]!;

      expect(saved.headerArtworkId, artwork.id);
      expect(saved.topArtistsArtworkId, original.topArtistsArtworkId);
      expect(saved.updatedAt, now);
    });

    test(
      'assigns Top Artists artwork without changing header artwork',
      () async {
        final original = _artist(headerArtworkId: 'artwork_header');

        final artistRepository = _FakeArtistRepository(artists: [original]);

        final artworkRepository = _FakeArtworkAssetRepository();

        final service = _service(
          artworkRepository: artworkRepository,
          artistRepository: artistRepository,
        );

        final now = DateTime.utc(2026, 9, 12, 8, 30);

        final artwork = await service.assignArtistTopArtists(
          artistId: original.id,
          filePath: r'C:\Artwork\Top Artists.png',
          now: now,
        );

        final saved = artistRepository.artists[original.id]!;

        expect(saved.headerArtworkId, 'artwork_header');
        expect(saved.topArtistsArtworkId, artwork.id);
        expect(saved.updatedAt, now);
      },
    );

    test('clearArtistHeader clears only header artwork', () async {
      final original = _artist(
        headerArtworkId: 'artwork_header',
        topArtistsArtworkId: 'artwork_top',
      );

      final artistRepository = _FakeArtistRepository(artists: [original]);

      final service = _service(artistRepository: artistRepository);

      final now = DateTime.utc(2026, 9, 12, 9);

      await service.clearArtistHeader(original.id, now: now);

      final saved = artistRepository.artists[original.id]!;

      expect(saved.headerArtworkId, isNull);
      expect(saved.topArtistsArtworkId, 'artwork_top');
      expect(saved.updatedAt, now);
    });

    test('clearArtistTopArtists clears only Top Artists artwork', () async {
      final original = _artist(
        headerArtworkId: 'artwork_header',
        topArtistsArtworkId: 'artwork_top',
      );

      final artistRepository = _FakeArtistRepository(artists: [original]);

      final service = _service(artistRepository: artistRepository);

      final now = DateTime.utc(2026, 9, 12, 9, 30);

      await service.clearArtistTopArtists(original.id, now: now);

      final saved = artistRepository.artists[original.id]!;

      expect(saved.headerArtworkId, 'artwork_header');
      expect(saved.topArtistsArtworkId, isNull);
      expect(saved.updatedAt, now);
    });

    test('missing artist fails before artwork asset is created', () async {
      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(artworkRepository: artworkRepository);

      await expectLater(
        () => service.assignArtistHeader(
          artistId: 'artist_missing',
          filePath: r'C:\Artwork\Missing.jpg',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Artist not found: artist_missing',
          ),
        ),
      );

      expect(artworkRepository.createdAssets, isEmpty);
      expect(artworkRepository.normalizedPathLookups, isEmpty);
    });
  });

  group('ArtworkAssignmentService album edition artwork', () {
    test('assigns artwork to album edition', () async {
      final original = _albumEdition();

      final editionRepository = _FakeAlbumEditionRepository(
        editions: [original],
      );

      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(
        artworkRepository: artworkRepository,
        albumEditionRepository: editionRepository,
      );

      final now = DateTime.utc(2026, 9, 12, 10);

      final artwork = await service.assignAlbumEdition(
        albumEditionId: original.id,
        filePath: r'C:\Artwork\Album Cover.jpg',
        now: now,
      );

      final saved = editionRepository.editions[original.id]!;

      expect(saved.artworkId, artwork.id);
      expect(saved.updatedAt, now);
    });

    test('clearAlbumEdition clears artwork reference', () async {
      final original = _albumEdition(artworkId: 'artwork_album');

      final editionRepository = _FakeAlbumEditionRepository(
        editions: [original],
      );

      final service = _service(albumEditionRepository: editionRepository);

      final now = DateTime.utc(2026, 9, 12, 10, 30);

      await service.clearAlbumEdition(original.id, now: now);

      final saved = editionRepository.editions[original.id]!;

      expect(saved.artworkId, isNull);
      expect(saved.updatedAt, now);
    });

    test(
      'missing album edition fails before artwork asset is created',
      () async {
        final artworkRepository = _FakeArtworkAssetRepository();

        final service = _service(artworkRepository: artworkRepository);

        await expectLater(
          () => service.assignAlbumEdition(
            albumEditionId: 'edition_missing',
            filePath: r'C:\Artwork\Missing Album.jpg',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Album edition not found: edition_missing',
            ),
          ),
        );

        expect(artworkRepository.createdAssets, isEmpty);
        expect(artworkRepository.normalizedPathLookups, isEmpty);
      },
    );
  });

  group('ArtworkAssignmentService song artwork', () {
    test('assigns artwork to song and updates timestamp', () async {
      final original = _song();

      final songRepository = _FakeSongRepository(songs: [original]);

      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(
        artworkRepository: artworkRepository,
        songRepository: songRepository,
      );

      final now = DateTime.utc(2026, 9, 12, 11);

      final artwork = await service.assignSong(
        songId: original.id,
        filePath: r'C:\Artwork\Song Cover.jpg',
        now: now,
      );

      final saved = songRepository.songs[original.id]!;

      expect(saved.artworkId, artwork.id);
      expect(saved.updatedAt, now);
    });

    test('clearSong clears artwork reference', () async {
      final original = _song(artworkId: 'artwork_song');

      final songRepository = _FakeSongRepository(songs: [original]);

      final service = _service(songRepository: songRepository);

      final now = DateTime.utc(2026, 9, 12, 11, 30);

      await service.clearSong(original.id, now: now);

      final saved = songRepository.songs[original.id]!;

      expect(saved.artworkId, isNull);
      expect(saved.updatedAt, now);
    });

    test('missing song fails before artwork asset is created', () async {
      final artworkRepository = _FakeArtworkAssetRepository();

      final service = _service(artworkRepository: artworkRepository);

      await expectLater(
        () => service.assignSong(
          songId: 'song_missing',
          filePath: r'C:\Artwork\Missing Song.jpg',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Song not found: song_missing',
          ),
        ),
      );

      expect(artworkRepository.createdAssets, isEmpty);
      expect(artworkRepository.normalizedPathLookups, isEmpty);
    });
  });
}

ArtworkAssignmentService _service({
  _FakeArtworkAssetRepository? artworkRepository,
  _FakeArtistRepository? artistRepository,
  _FakeAlbumEditionRepository? albumEditionRepository,
  _FakeSongRepository? songRepository,
}) {
  return ArtworkAssignmentService(
    artworkAssetRepository: artworkRepository ?? _FakeArtworkAssetRepository(),
    artistRepository: artistRepository ?? _FakeArtistRepository(),
    albumEditionRepository:
        albumEditionRepository ?? _FakeAlbumEditionRepository(),
    songRepository: songRepository ?? _FakeSongRepository(),
  );
}

Artist _artist({String? headerArtworkId, String? topArtistsArtworkId}) {
  return Artist(
    id: 'artist_1',
    name: 'Artist',
    canonicalName: 'artist',
    headerArtworkId: headerArtworkId,
    topArtistsArtworkId: topArtistsArtworkId,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

AlbumEdition _albumEdition({String? artworkId}) {
  return AlbumEdition(
    id: 'edition_1',
    albumId: 'album_1',
    title: 'Album',
    type: AlbumEditionType.standard,
    isPrimary: true,
    artworkId: artworkId,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Song _song({String? artworkId}) {
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
    featuredArtists: const [],
    artworkId: artworkId,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

class _FakeArtworkAssetRepository implements ArtworkAssetRepository {
  _FakeArtworkAssetRepository({List<ArtworkAsset> assets = const []})
    : _assets = {for (final asset in assets) asset.normalizedPath: asset};

  final Map<String, ArtworkAsset> _assets;

  final List<ArtworkAsset> createdAssets = [];
  final List<String> normalizedPathLookups = [];

  @override
  Future<void> create(ArtworkAsset artworkAsset) async {
    createdAssets.add(artworkAsset);
    _assets[artworkAsset.normalizedPath] = artworkAsset;
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) async {
    _assets[artworkAsset.normalizedPath] = artworkAsset;
  }

  @override
  Future<ArtworkAsset?> getById(String id) async {
    for (final asset in _assets.values) {
      if (asset.id == id) {
        return asset;
      }
    }

    return null;
  }

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) async {
    normalizedPathLookups.add(normalizedPath);
    return _assets[normalizedPath];
  }

  @override
  Future<List<ArtworkAsset>> getAll() async {
    return List.unmodifiable(_assets.values);
  }
}

class _FakeArtistRepository implements ArtistRepository {
  _FakeArtistRepository({List<Artist> artists = const []})
    : artists = {for (final artist in artists) artist.id: artist};

  final Map<String, Artist> artists;
  final List<Artist> savedArtists = [];

  @override
  Future<void> create(Artist artist) async {
    artists[artist.id] = artist;
  }

  @override
  Future<void> save(Artist artist) async {
    savedArtists.add(artist);
    artists[artist.id] = artist;
  }

  @override
  Future<Artist?> getById(String id) async {
    return artists[id];
  }

  @override
  Future<List<Artist>> getAll() async {
    return List.unmodifiable(artists.values);
  }
}

class _FakeAlbumEditionRepository implements AlbumEditionRepository {
  _FakeAlbumEditionRepository({List<AlbumEdition> editions = const []})
    : editions = {for (final edition in editions) edition.id: edition};

  final Map<String, AlbumEdition> editions;
  final List<AlbumEdition> savedEditions = [];

  @override
  Future<void> create(AlbumEdition edition) async {
    editions[edition.id] = edition;
  }

  @override
  Future<void> save(AlbumEdition edition) async {
    savedEditions.add(edition);
    editions[edition.id] = edition;
  }

  @override
  Future<AlbumEdition?> getById(String id) async {
    return editions[id];
  }

  @override
  Future<List<AlbumEdition>> getAll() async {
    return List.unmodifiable(editions.values);
  }

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async {
    return editions.values
        .where((edition) => edition.albumId == albumId)
        .toList(growable: false);
  }
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository({List<Song> songs = const []})
    : songs = {for (final song in songs) song.id: song};

  final Map<String, Song> songs;
  final List<Song> savedSongs = [];

  @override
  Future<void> create(Song song) async {
    songs[song.id] = song;
  }

  @override
  Future<void> save(Song song) async {
    savedSongs.add(song);
    songs[song.id] = song;
  }

  @override
  Future<Song?> getById(String id) async {
    return songs[id];
  }

  @override
  Future<List<Song>> getAll() async {
    return List.unmodifiable(songs.values);
  }

  @override
  Future<List<Song>> getByArtistId(String artistId) async {
    return songs.values
        .where((song) => song.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<Song>> getByAlbumId(String albumId) async {
    return songs.values
        .where((song) => song.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<Song>> getByEditionId(String albumEditionId) async {
    return songs.values
        .where((song) => song.albumEditionId == albumEditionId)
        .toList(growable: false);
  }

  @override
  Future<List<Song>> getRecentlyAdded(int limit) async {
    final values = songs.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return values.take(limit).toList(growable: false);
  }
}
