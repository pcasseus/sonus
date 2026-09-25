import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('joined track query returns complete library projection', () async {
    final fixture = await _createFixture(appDatabase);

    final queryDao = LibraryQueryDao(fixture.db);

    final tracks = await queryDao.findTracks();

    expect(tracks, hasLength(3));

    final track = tracks.firstWhere(
      (item) => item.songId == fixture.alphaSong.id,
    );

    expect(track.title, 'Alpha Track');
    expect(track.artistId, fixture.artist.id);
    expect(track.artistName, 'Query Artist');
    expect(track.albumId, fixture.album.id);
    expect(track.albumTitle, 'Query Album');
    expect(track.albumEditionId, fixture.standardEdition.id);
    expect(track.albumEditionTitle, 'Query Album');
    expect(track.albumEditionType, AlbumEditionType.standard);
    expect(track.trackNumber, 1);
    expect(track.discNumber, 2);
    expect(track.durationSeconds, 181);
    expect(track.isSingle, isFalse);
    expect(track.featuredArtists, ['Featured Artist']);
    expect(track.filePath, r'C:\Music\Query Artist\Query Album\Alpha.mp3');
    expect(track.isAvailable, isTrue);
    expect(track.dateAdded, fixture.alphaSong.createdAt);
  });

  test('track query orders songs by title deterministically', () async {
    final fixture = await _createFixture(appDatabase);

    final tracks = await LibraryQueryDao(
      fixture.db,
    ).findTracks(order: LibraryTrackOrder.title);

    expect(tracks.map((track) => track.songId).toList(), [
      'song_alpha',
      'song_beta',
      'song_zulu',
    ]);
  });

  test(
    'track query orders songs by artist then album disc and track',
    () async {
      final fixture = await _createFixture(appDatabase);

      final secondArtist = Artist(
        id: 'artist_aardvark',
        name: 'Aardvark Artist',
        canonicalName: 'aardvark artist',
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      final secondAlbum = Album(
        id: 'album_aardvark',
        artistId: secondArtist.id,
        title: 'Aardvark Album',
        canonicalTitle: 'aardvark album',
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      final secondEdition = AlbumEdition(
        id: 'edition_aardvark',
        albumId: secondAlbum.id,
        title: 'Aardvark Album',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      final secondSong = Song(
        id: 'song_aardvark',
        artistId: secondArtist.id,
        albumId: secondAlbum.id,
        albumEditionId: secondEdition.id,
        title: 'Later Alphabetically',
        canonicalTitle: 'later alphabetically',
        trackNumber: 1,
        durationSeconds: 200,
        isSingle: false,
        featuredArtists: const [],
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      await ArtistDao(fixture.db).insert(secondArtist);
      await AlbumDao(fixture.db).insert(secondAlbum);
      await AlbumEditionDao(fixture.db).insert(secondEdition);
      await SongDao(fixture.db).insert(secondSong);

      final tracks = await LibraryQueryDao(
        fixture.db,
      ).findTracks(order: LibraryTrackOrder.artist);

      expect(tracks.first.songId, secondSong.id);

      expect(
        tracks
            .where((track) => track.artistId == fixture.artist.id)
            .map((track) => track.songId)
            .toList(),
        ['song_beta', 'song_zulu', 'song_alpha'],
      );
    },
  );

  test('track query orders newest additions first', () async {
    final fixture = await _createFixture(appDatabase);

    final tracks = await LibraryQueryDao(
      fixture.db,
    ).findTracks(order: LibraryTrackOrder.dateAdded);

    expect(tracks.map((track) => track.songId).toList(), [
      'song_zulu',
      'song_beta',
      'song_alpha',
    ]);
  });

  test('track query resolves a track by permanent song id', () async {
    final fixture = await _createFixture(appDatabase);

    final queryDao = LibraryQueryDao(fixture.db);

    final track = await queryDao.findTrackById(fixture.betaSong.id);

    expect(track, isNotNull);
    expect(track?.songId, fixture.betaSong.id);
    expect(track?.title, fixture.betaSong.title);
    expect(track?.artistId, fixture.artist.id);
    expect(track?.albumId, fixture.album.id);
  });

  test('track lookup returns null for unknown song id', () async {
    final fixture = await _createFixture(appDatabase);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById('missing_song');

    expect(track, isNull);
  });

  test(
    'track projection prefers an available media binding deterministically',
    () async {
      final fixture = await _createFixture(appDatabase);

      final bindingDao = MediaFileBindingDao(fixture.db);

      final olderUnavailable = MediaFileBinding(
        id: 'media_unavailable',
        songId: fixture.betaSong.id,
        filePath: r'C:\Old\Beta.mp3',
        normalizedPath: 'c:/old/beta.mp3',
        isAvailable: false,
        lastSeenAt: DateTime.utc(2026, 9, 9),
        createdAt: DateTime.utc(2026, 9, 9),
        updatedAt: DateTime.utc(2026, 9, 9),
      );

      final newerAvailable = MediaFileBinding(
        id: 'media_available',
        songId: fixture.betaSong.id,
        filePath: r'D:\Music\Beta.mp3',
        normalizedPath: 'd:/music/beta.mp3',
        isAvailable: true,
        lastSeenAt: DateTime.utc(2026, 9, 11),
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      await bindingDao.insert(olderUnavailable);
      await bindingDao.insert(newerAvailable);

      final track = await LibraryQueryDao(
        fixture.db,
      ).findTrackById(fixture.betaSong.id);

      expect(track, isNotNull);
      expect(track?.filePath, r'D:\Music\Beta.mp3');
      expect(track?.isAvailable, isTrue);
    },
  );

  test('track without a media binding is represented as unavailable', () async {
    final fixture = await _createFixture(appDatabase);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById(fixture.zuluSong.id);

    expect(track, isNotNull);
    expect(track?.filePath, isNull);
    expect(track?.isAvailable, isFalse);
  });

  test(
    'album query returns artist, primary edition metadata and track count',
    () async {
      final fixture = await _createFixture(appDatabase);

      final albums = await LibraryQueryDao(fixture.db).findAlbums();

      expect(albums, hasLength(1));

      final album = albums.single;

      expect(album.albumId, fixture.album.id);
      expect(album.title, 'Query Album');
      expect(album.artistId, fixture.artist.id);
      expect(album.artistName, 'Query Artist');

      expect(album.primaryEditionId, fixture.standardEdition.id);
      expect(album.primaryEditionTitle, 'Query Album');
      expect(album.primaryEditionType, AlbumEditionType.standard);

      expect(album.releaseDate, DateTime.utc(2026, 1, 15));
      expect(album.genre, 'Pop');

      expect(album.trackCount, 3);
      expect(album.dateAdded, fixture.album.createdAt);
    },
  );

  test('album query counts songs across album editions only once', () async {
    final fixture = await _createFixture(appDatabase);

    final deluxeSong = Song(
      id: 'song_deluxe',
      artistId: fixture.artist.id,
      albumId: fixture.album.id,
      albumEditionId: fixture.deluxeEdition.id,
      title: 'Deluxe Track',
      canonicalTitle: 'deluxe track',
      trackNumber: 4,
      durationSeconds: 220,
      isSingle: false,
      featuredArtists: const [],
      createdAt: DateTime.utc(2026, 9, 13),
      updatedAt: DateTime.utc(2026, 9, 13),
    );

    await SongDao(fixture.db).insert(deluxeSong);

    final albums = await LibraryQueryDao(fixture.db).findAlbums();

    expect(albums.single.trackCount, 4);
  });

  test('artist query returns album and song counts', () async {
    final fixture = await _createFixture(appDatabase);

    final artists = await LibraryQueryDao(fixture.db).findArtists();

    expect(artists, hasLength(1));

    final artist = artists.single;

    expect(artist.artistId, fixture.artist.id);
    expect(artist.name, 'Query Artist');
    expect(artist.albumCount, 1);
    expect(artist.songCount, 3);
    expect(artist.dateAdded, fixture.artist.createdAt);
  });

  test('artist query exposes blacklist state without hiding artist', () async {
    final fixture = await _createFixture(appDatabase);

    final artistDao = ArtistDao(fixture.db);

    await artistDao.update(
      fixture.artist.copyWith(
        isBlacklisted: true,
        updatedAt: DateTime.utc(2026, 9, 13, 14),
      ),
    );

    final artists = await LibraryQueryDao(fixture.db).findArtists();

    expect(artists, hasLength(1));

    final artist = artists.single;

    expect(artist.artistId, fixture.artist.id);
    expect(artist.isBlacklisted, isTrue);
  });

  test('artist query keeps artists with no albums or songs', () async {
    final fixture = await _createFixture(appDatabase);

    final emptyArtist = Artist(
      id: 'artist_empty',
      name: 'Empty Artist',
      canonicalName: 'empty artist',
      createdAt: DateTime.utc(2026, 9, 14),
      updatedAt: DateTime.utc(2026, 9, 14),
    );

    await ArtistDao(fixture.db).insert(emptyArtist);

    final artists = await LibraryQueryDao(fixture.db).findArtists();

    final projected = artists.firstWhere(
      (artist) => artist.artistId == emptyArtist.id,
    );

    expect(projected.albumCount, 0);
    expect(projected.songCount, 0);
  });

  test('album query chooses one primary edition deterministically', () async {
    final fixture = await _createFixture(appDatabase);

    final secondPrimaryEdition = AlbumEdition(
      id: 'edition_second_primary',
      albumId: fixture.album.id,
      title: 'Earlier Primary',
      type: AlbumEditionType.expanded,
      isPrimary: true,
      releaseDate: DateTime.utc(2025, 12, 1),
      genre: 'Alternative',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await AlbumEditionDao(fixture.db).insert(secondPrimaryEdition);

    final albums = await LibraryQueryDao(fixture.db).findAlbums();

    expect(albums, hasLength(1));
    expect(albums.single.albumId, fixture.album.id);
    expect(albums.single.primaryEditionId, secondPrimaryEdition.id);
    expect(albums.single.primaryEditionType, AlbumEditionType.expanded);
  });

  test('recent track query respects newest-first limit', () async {
    final fixture = await _createFixture(appDatabase);

    final tracks = await LibraryQueryDao(fixture.db).findRecentlyAddedTracks(2);

    expect(tracks.map((track) => track.songId).toList(), [
      'song_zulu',
      'song_beta',
    ]);
  });

  test(
    'recent track query returns empty list for non-positive limit',
    () async {
      final fixture = await _createFixture(appDatabase);

      final queryDao = LibraryQueryDao(fixture.db);

      expect(await queryDao.findRecentlyAddedTracks(0), isEmpty);
      expect(await queryDao.findRecentlyAddedTracks(-1), isEmpty);
    },
  );

  test('artist track query returns only requested artist', () async {
    final fixture = await _createFixture(appDatabase);

    final otherArtist = Artist(
      id: 'artist_other',
      name: 'Other Artist',
      canonicalName: 'other artist',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final otherAlbum = Album(
      id: 'album_other',
      artistId: otherArtist.id,
      title: 'Other Album',
      canonicalTitle: 'other album',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final otherEdition = AlbumEdition(
      id: 'edition_other',
      albumId: otherAlbum.id,
      title: 'Other Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final otherSong = Song(
      id: 'song_other',
      artistId: otherArtist.id,
      albumId: otherAlbum.id,
      albumEditionId: otherEdition.id,
      title: 'Other Track',
      canonicalTitle: 'other track',
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await ArtistDao(fixture.db).insert(otherArtist);
    await AlbumDao(fixture.db).insert(otherAlbum);
    await AlbumEditionDao(fixture.db).insert(otherEdition);
    await SongDao(fixture.db).insert(otherSong);

    final tracks = await LibraryQueryDao(
      fixture.db,
    ).findTracksByArtistId(fixture.artist.id);

    expect(tracks, hasLength(3));
    expect(
      tracks.every((track) => track.artistId == fixture.artist.id),
      isTrue,
    );
  });

  test('album track query includes songs across album editions', () async {
    final fixture = await _createFixture(appDatabase);

    final deluxeSong = Song(
      id: 'song_deluxe_profile',
      artistId: fixture.artist.id,
      albumId: fixture.album.id,
      albumEditionId: fixture.deluxeEdition.id,
      title: 'Deluxe Profile Track',
      canonicalTitle: 'deluxe profile track',
      trackNumber: 4,
      durationSeconds: 220,
      isSingle: false,
      featuredArtists: const [],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await SongDao(fixture.db).insert(deluxeSong);

    final tracks = await LibraryQueryDao(
      fixture.db,
    ).findTracksByAlbumId(fixture.album.id);

    expect(tracks, hasLength(4));
    expect(tracks.map((track) => track.songId), contains(deluxeSong.id));
  });

  test(
    'album lookup returns complete album projection by permanent id',
    () async {
      final fixture = await _createFixture(appDatabase);

      final album = await LibraryQueryDao(
        fixture.db,
      ).findAlbumById(fixture.album.id);

      expect(album, isNotNull);

      expect(album?.albumId, fixture.album.id);
      expect(album?.title, 'Query Album');

      expect(album?.artistId, fixture.artist.id);
      expect(album?.artistName, 'Query Artist');

      expect(album?.primaryEditionId, fixture.standardEdition.id);
      expect(album?.primaryEditionTitle, 'Query Album');
      expect(album?.primaryEditionType, AlbumEditionType.standard);

      expect(album?.releaseDate, DateTime.utc(2026, 1, 15));
      expect(album?.genre, 'Pop');

      expect(album?.trackCount, 3);
      expect(album?.dateAdded, fixture.album.createdAt);
    },
  );

  test('album lookup returns null for unknown album id', () async {
    final fixture = await _createFixture(appDatabase);

    final album = await LibraryQueryDao(
      fixture.db,
    ).findAlbumById('missing_album');

    expect(album, isNull);
  });

  test('artist lookup resolves permanent artist id', () async {
    final fixture = await _createFixture(appDatabase);

    final artist = await LibraryQueryDao(
      fixture.db,
    ).findArtistById(fixture.artist.id);

    expect(artist, isNotNull);
    expect(artist?.artistId, fixture.artist.id);
  });

  test('artist lookup preserves blacklist state', () async {
    final fixture = await _createFixture(appDatabase);

    final artistDao = ArtistDao(fixture.db);

    await artistDao.update(
      fixture.artist.copyWith(
        isBlacklisted: true,
        updatedAt: DateTime.utc(2026, 9, 13, 14),
      ),
    );

    final artist = await LibraryQueryDao(
      fixture.db,
    ).findArtistById(fixture.artist.id);

    expect(artist, isNotNull);
    expect(artist?.artistId, fixture.artist.id);
    expect(artist?.isBlacklisted, isTrue);
  });

  test('artist album query returns only requested artist albums', () async {
    final fixture = await _createFixture(appDatabase);

    final albums = await LibraryQueryDao(
      fixture.db,
    ).findAlbumsByArtistId(fixture.artist.id);

    expect(albums, hasLength(1));
    expect(albums.single.albumId, fixture.album.id);
  });

  test('recent albums respect newest-first limit', () async {
    final fixture = await _createFixture(appDatabase);

    final secondAlbum = Album(
      id: 'album_newer',
      artistId: fixture.artist.id,
      title: 'Newer Album',
      canonicalTitle: 'newer album',
      createdAt: DateTime.utc(2026, 9, 20),
      updatedAt: DateTime.utc(2026, 9, 20),
    );

    await AlbumDao(fixture.db).insert(secondAlbum);

    final albums = await LibraryQueryDao(fixture.db).findRecentlyAddedAlbums(1);

    expect(albums, hasLength(1));
    expect(albums.single.albumId, secondAlbum.id);
  });

  test('album projection exposes primary edition artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final albums = await LibraryQueryDao(fixture.db).findAlbums();

    expect(albums, hasLength(1));

    final album = albums.single;

    expect(album.albumId, fixture.album.id);
    expect(album.artworkId, fixture.standardArtwork.id);
    expect(album.artworkPath, fixture.standardArtwork.filePath);
  });

  test('album lookup exposes the same primary edition artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final queryDao = LibraryQueryDao(fixture.db);

    final listAlbum = (await queryDao.findAlbums()).single;
    final directAlbum = await queryDao.findAlbumById(fixture.album.id);

    expect(directAlbum, isNotNull);
    expect(directAlbum?.artworkId, listAlbum.artworkId);
    expect(directAlbum?.artworkPath, listAlbum.artworkPath);
    expect(directAlbum?.artworkId, fixture.standardArtwork.id);
    expect(directAlbum?.artworkPath, fixture.standardArtwork.filePath);
  });

  test('track projection falls back to album edition artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById(fixture.betaSong.id);

    expect(track, isNotNull);
    expect(track?.artworkId, fixture.standardArtwork.id);
    expect(track?.artworkPath, fixture.standardArtwork.filePath);
  });

  test('track-specific artwork overrides album edition artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById(fixture.alphaSong.id);

    expect(track, isNotNull);
    expect(track?.artworkId, fixture.songArtwork.id);
    expect(track?.artworkPath, fixture.songArtwork.filePath);
  });

  test('track projection remains null when no artwork exists', () async {
    final fixture = await _createFixture(appDatabase);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById(fixture.betaSong.id);

    expect(track, isNotNull);
    expect(track?.artworkId, isNull);
    expect(track?.artworkPath, isNull);
  });

  test('artist projection exposes header and Top Artists artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final artists = await LibraryQueryDao(fixture.db).findArtists();

    expect(artists, hasLength(1));

    final artist = artists.single;

    expect(artist.artistId, fixture.artist.id);

    expect(artist.headerArtworkId, fixture.artistHeaderArtwork.id);
    expect(artist.headerArtworkPath, fixture.artistHeaderArtwork.filePath);

    expect(artist.topArtistsArtworkId, fixture.topArtistsArtwork.id);
    expect(artist.topArtistsArtworkPath, fixture.topArtistsArtwork.filePath);
  });

  test('artist lookup preserves artwork projection', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final artist = await LibraryQueryDao(
      fixture.db,
    ).findArtistById(fixture.artist.id);

    expect(artist, isNotNull);
    expect(artist?.headerArtworkId, fixture.artistHeaderArtwork.id);
    expect(artist?.headerArtworkPath, fixture.artistHeaderArtwork.filePath);
    expect(artist?.topArtistsArtworkId, fixture.topArtistsArtwork.id);
    expect(artist?.topArtistsArtworkPath, fixture.topArtistsArtwork.filePath);
  });

  test('artist projection remains null when no artwork exists', () async {
    final fixture = await _createFixture(appDatabase);

    final artist = await LibraryQueryDao(
      fixture.db,
    ).findArtistById(fixture.artist.id);

    expect(artist, isNotNull);
    expect(artist?.headerArtworkId, isNull);
    expect(artist?.headerArtworkPath, isNull);
    expect(artist?.topArtistsArtworkId, isNull);
    expect(artist?.topArtistsArtworkPath, isNull);
  });

  test('deluxe track resolves deluxe edition artwork', () async {
    final fixture = await _createArtworkFixture(appDatabase);

    final deluxeSong = Song(
      id: 'song_deluxe_artwork',
      artistId: fixture.artist.id,
      albumId: fixture.album.id,
      albumEditionId: fixture.deluxeEdition.id,
      title: 'Deluxe Artwork Track',
      canonicalTitle: 'deluxe artwork track',
      trackNumber: 4,
      durationSeconds: 220,
      isSingle: false,
      featuredArtists: const [],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await SongDao(fixture.db).insert(deluxeSong);

    final track = await LibraryQueryDao(
      fixture.db,
    ).findTrackById(deluxeSong.id);

    expect(track, isNotNull);
    expect(track?.artworkId, fixture.deluxeArtwork.id);
    expect(track?.artworkPath, fixture.deluxeArtwork.filePath);
  });
  group('library search', () {
    test('blank query returns empty results', () async {
      final db = await appDatabase.database;
      final dao = LibraryQueryDao(db);

      final results = await dao.search('   ');

      expect(results.isEmpty, isTrue);
      expect(results.totalCount, 0);
    });

    test('search matches artist name case-insensitively', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('QUERY ART');

      expect(
        results.artists.map((artist) => artist.artistId),
        contains(fixture.artist.id),
      );
    });

    test('search matches partial album title', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('uery alb');

      expect(
        results.albums.map((album) => album.albumId),
        contains(fixture.album.id),
      );
    });

    test('search matches track title', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('alpha');

      expect(
        results.tracks.map((track) => track.songId),
        contains(fixture.alphaSong.id),
      );
    });

    test('search matches track artist name', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('query artist');

      expect(results.tracks, isNotEmpty);
      expect(
        results.tracks.every((track) => track.artistId == fixture.artist.id),
        isTrue,
      );
    });

    test('search matches track album title', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('query album');

      expect(results.tracks, isNotEmpty);
      expect(
        results.tracks.every((track) => track.albumId == fixture.album.id),
        isTrue,
      );
    });

    test(
      'search ranks exact track title before prefix and contains matches',
      () async {
        final fixture = await _createFixture(appDatabase);
        final dao = LibraryQueryDao(fixture.db);

        final now = DateTime.utc(2026, 9, 25);

        final exactSong = Song(
          id: 'song_search_exact',
          artistId: fixture.artist.id,
          albumId: fixture.album.id,
          albumEditionId: fixture.standardEdition.id,
          title: 'Alpha',
          canonicalTitle: 'alpha',
          trackNumber: 90,
          durationSeconds: 180,
          isSingle: false,
          createdAt: now,
          updatedAt: now,
        );

        final prefixSong = Song(
          id: 'song_search_prefix',
          artistId: fixture.artist.id,
          albumId: fixture.album.id,
          albumEditionId: fixture.standardEdition.id,
          title: 'Alpha Lights',
          canonicalTitle: 'alpha lights',
          trackNumber: 91,
          durationSeconds: 180,
          isSingle: false,
          createdAt: now,
          updatedAt: now,
        );

        final containsSong = Song(
          id: 'song_search_contains',
          artistId: fixture.artist.id,
          albumId: fixture.album.id,
          albumEditionId: fixture.standardEdition.id,
          title: 'The Alpha Song',
          canonicalTitle: 'the alpha song',
          trackNumber: 92,
          durationSeconds: 180,
          isSingle: false,
          createdAt: now,
          updatedAt: now,
        );

        await SongDao(fixture.db).insert(exactSong);
        await SongDao(fixture.db).insert(prefixSong);
        await SongDao(fixture.db).insert(containsSong);

        final results = await dao.search('alpha');

        final ids = results.tracks.map((track) => track.songId).toList();

        expect(ids.indexOf(exactSong.id), lessThan(ids.indexOf(prefixSong.id)));
        expect(
          ids.indexOf(prefixSong.id),
          lessThan(ids.indexOf(containsSong.id)),
        );
      },
    );

    test('search normalizes repeated whitespace', () async {
      final fixture = await _createFixture(appDatabase);
      final dao = LibraryQueryDao(fixture.db);

      final results = await dao.search('  query    artist  ');

      expect(
        results.artists.map((artist) => artist.artistId),
        contains(fixture.artist.id),
      );
    });
  });
}

Future<_QueryFixture> _createFixture(AppDatabase appDatabase) async {
  final db = await appDatabase.database;

  final artistDao = ArtistDao(db);
  final albumDao = AlbumDao(db);
  final editionDao = AlbumEditionDao(db);
  final songDao = SongDao(db);
  final bindingDao = MediaFileBindingDao(db);

  final artist = Artist(
    id: 'artist_query',
    name: 'Query Artist',
    canonicalName: 'query artist',
    createdAt: DateTime.utc(2026, 9, 10, 8),
    updatedAt: DateTime.utc(2026, 9, 10, 8),
  );

  final album = Album(
    id: 'album_query',
    artistId: artist.id,
    title: 'Query Album',
    canonicalTitle: 'query album',
    createdAt: DateTime.utc(2026, 9, 10, 9),
    updatedAt: DateTime.utc(2026, 9, 10, 9),
  );

  final standardEdition = AlbumEdition(
    id: 'edition_standard',
    albumId: album.id,
    title: 'Query Album',
    type: AlbumEditionType.standard,
    isPrimary: true,
    releaseDate: DateTime.utc(2026, 1, 15),
    genre: 'Pop',
    createdAt: DateTime.utc(2026, 9, 10, 9),
    updatedAt: DateTime.utc(2026, 9, 10, 9),
  );

  final deluxeEdition = AlbumEdition(
    id: 'edition_deluxe',
    albumId: album.id,
    title: 'Query Album Deluxe',
    type: AlbumEditionType.deluxe,
    isPrimary: false,
    releaseDate: DateTime.utc(2026, 6, 20),
    genre: 'Pop',
    createdAt: DateTime.utc(2026, 9, 10, 10),
    updatedAt: DateTime.utc(2026, 9, 10, 10),
  );

  final alphaSong = Song(
    id: 'song_alpha',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Alpha Track',
    canonicalTitle: 'alpha track',
    trackNumber: 1,
    discNumber: 2,
    durationSeconds: 181,
    isSingle: false,
    featuredArtists: const ['Featured Artist'],
    createdAt: DateTime.utc(2026, 9, 10, 11),
    updatedAt: DateTime.utc(2026, 9, 10, 11),
  );

  final betaSong = Song(
    id: 'song_beta',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Beta Track',
    canonicalTitle: 'beta track',
    trackNumber: 2,
    durationSeconds: 182,
    isSingle: true,
    featuredArtists: const [],
    createdAt: DateTime.utc(2026, 9, 11, 11),
    updatedAt: DateTime.utc(2026, 9, 11, 11),
  );

  final zuluSong = Song(
    id: 'song_zulu',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Zulu Track',
    canonicalTitle: 'zulu track',
    trackNumber: 3,
    durationSeconds: 183,
    isSingle: false,
    featuredArtists: const [],
    createdAt: DateTime.utc(2026, 9, 12, 11),
    updatedAt: DateTime.utc(2026, 9, 12, 11),
  );

  await artistDao.insert(artist);
  await albumDao.insert(album);
  await editionDao.insert(standardEdition);
  await editionDao.insert(deluxeEdition);

  await songDao.insert(alphaSong);
  await songDao.insert(betaSong);
  await songDao.insert(zuluSong);

  await bindingDao.insert(
    MediaFileBinding(
      id: 'media_alpha',
      songId: alphaSong.id,
      filePath: r'C:\Music\Query Artist\Query Album\Alpha.mp3',
      normalizedPath: 'c:/music/query artist/query album/alpha.mp3',
      isAvailable: true,
      lastSeenAt: DateTime.utc(2026, 9, 10, 12),
      createdAt: DateTime.utc(2026, 9, 10, 12),
      updatedAt: DateTime.utc(2026, 9, 10, 12),
    ),
  );

  return _QueryFixture(
    db: db,
    artist: artist,
    album: album,
    standardEdition: standardEdition,
    deluxeEdition: deluxeEdition,
    alphaSong: alphaSong,
    betaSong: betaSong,
    zuluSong: zuluSong,
  );
}

Future<_ArtworkQueryFixture> _createArtworkFixture(
  AppDatabase appDatabase,
) async {
  final db = await appDatabase.database;

  final artworkDao = ArtworkAssetDao(db);
  final artistDao = ArtistDao(db);
  final albumDao = AlbumDao(db);
  final editionDao = AlbumEditionDao(db);
  final songDao = SongDao(db);
  final bindingDao = MediaFileBindingDao(db);

  final createdAt = DateTime.utc(2026, 9, 10, 7);

  final artistHeaderArtwork = ArtworkAsset(
    id: 'artwork_artist_header',
    filePath: r'C:\Artwork\Query Artist\header.jpg',
    normalizedPath: 'c:/artwork/query artist/header.jpg',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final topArtistsArtwork = ArtworkAsset(
    id: 'artwork_top_artists',
    filePath: r'C:\Artwork\Query Artist\top-artists.jpg',
    normalizedPath: 'c:/artwork/query artist/top-artists.jpg',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final standardArtwork = ArtworkAsset(
    id: 'artwork_standard',
    filePath: r'C:\Artwork\Query Album\standard.jpg',
    normalizedPath: 'c:/artwork/query album/standard.jpg',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final deluxeArtwork = ArtworkAsset(
    id: 'artwork_deluxe',
    filePath: r'C:\Artwork\Query Album\deluxe.jpg',
    normalizedPath: 'c:/artwork/query album/deluxe.jpg',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final songArtwork = ArtworkAsset(
    id: 'artwork_song_alpha',
    filePath: r'C:\Artwork\Query Album\alpha.jpg',
    normalizedPath: 'c:/artwork/query album/alpha.jpg',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  await artworkDao.insert(artistHeaderArtwork);
  await artworkDao.insert(topArtistsArtwork);
  await artworkDao.insert(standardArtwork);
  await artworkDao.insert(deluxeArtwork);
  await artworkDao.insert(songArtwork);

  final artist = Artist(
    id: 'artist_query',
    name: 'Query Artist',
    canonicalName: 'query artist',
    headerArtworkId: artistHeaderArtwork.id,
    topArtistsArtworkId: topArtistsArtwork.id,
    createdAt: DateTime.utc(2026, 9, 10, 8),
    updatedAt: DateTime.utc(2026, 9, 10, 8),
  );

  final album = Album(
    id: 'album_query',
    artistId: artist.id,
    title: 'Query Album',
    canonicalTitle: 'query album',
    createdAt: DateTime.utc(2026, 9, 10, 9),
    updatedAt: DateTime.utc(2026, 9, 10, 9),
  );

  final standardEdition = AlbumEdition(
    id: 'edition_standard',
    albumId: album.id,
    title: 'Query Album',
    type: AlbumEditionType.standard,
    isPrimary: true,
    releaseDate: DateTime.utc(2026, 1, 15),
    genre: 'Pop',
    artworkId: standardArtwork.id,
    createdAt: DateTime.utc(2026, 9, 10, 9),
    updatedAt: DateTime.utc(2026, 9, 10, 9),
  );

  final deluxeEdition = AlbumEdition(
    id: 'edition_deluxe',
    albumId: album.id,
    title: 'Query Album Deluxe',
    type: AlbumEditionType.deluxe,
    isPrimary: false,
    releaseDate: DateTime.utc(2026, 6, 20),
    genre: 'Pop',
    artworkId: deluxeArtwork.id,
    createdAt: DateTime.utc(2026, 9, 10, 10),
    updatedAt: DateTime.utc(2026, 9, 10, 10),
  );

  final alphaSong = Song(
    id: 'song_alpha',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Alpha Track',
    canonicalTitle: 'alpha track',
    trackNumber: 1,
    durationSeconds: 181,
    isSingle: false,
    featuredArtists: const ['Featured Artist'],
    artworkId: songArtwork.id,
    createdAt: DateTime.utc(2026, 9, 10, 11),
    updatedAt: DateTime.utc(2026, 9, 10, 11),
  );

  final betaSong = Song(
    id: 'song_beta',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Beta Track',
    canonicalTitle: 'beta track',
    trackNumber: 2,
    durationSeconds: 182,
    isSingle: true,
    featuredArtists: const [],
    createdAt: DateTime.utc(2026, 9, 11, 11),
    updatedAt: DateTime.utc(2026, 9, 11, 11),
  );

  final zuluSong = Song(
    id: 'song_zulu',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: standardEdition.id,
    title: 'Zulu Track',
    canonicalTitle: 'zulu track',
    trackNumber: 3,
    durationSeconds: 183,
    isSingle: false,
    featuredArtists: const [],
    createdAt: DateTime.utc(2026, 9, 12, 11),
    updatedAt: DateTime.utc(2026, 9, 12, 11),
  );

  await artistDao.insert(artist);
  await albumDao.insert(album);
  await editionDao.insert(standardEdition);
  await editionDao.insert(deluxeEdition);

  await songDao.insert(alphaSong);
  await songDao.insert(betaSong);
  await songDao.insert(zuluSong);

  await bindingDao.insert(
    MediaFileBinding(
      id: 'media_alpha',
      songId: alphaSong.id,
      filePath: r'C:\Music\Query Artist\Query Album\Alpha.mp3',
      normalizedPath: 'c:/music/query artist/query album/alpha.mp3',
      isAvailable: true,
      lastSeenAt: DateTime.utc(2026, 9, 10, 12),
      createdAt: DateTime.utc(2026, 9, 10, 12),
      updatedAt: DateTime.utc(2026, 9, 10, 12),
    ),
  );

  return _ArtworkQueryFixture(
    db: db,
    artist: artist,
    album: album,
    standardEdition: standardEdition,
    deluxeEdition: deluxeEdition,
    alphaSong: alphaSong,
    betaSong: betaSong,
    zuluSong: zuluSong,
    artistHeaderArtwork: artistHeaderArtwork,
    topArtistsArtwork: topArtistsArtwork,
    standardArtwork: standardArtwork,
    deluxeArtwork: deluxeArtwork,
    songArtwork: songArtwork,
  );
}

class _QueryFixture {
  const _QueryFixture({
    required this.db,
    required this.artist,
    required this.album,
    required this.standardEdition,
    required this.deluxeEdition,
    required this.alphaSong,
    required this.betaSong,
    required this.zuluSong,
  });

  final Database db;

  final Artist artist;
  final Album album;

  final AlbumEdition standardEdition;
  final AlbumEdition deluxeEdition;

  final Song alphaSong;
  final Song betaSong;
  final Song zuluSong;
}

class _ArtworkQueryFixture {
  const _ArtworkQueryFixture({
    required this.db,
    required this.artist,
    required this.album,
    required this.standardEdition,
    required this.deluxeEdition,
    required this.alphaSong,
    required this.betaSong,
    required this.zuluSong,
    required this.artistHeaderArtwork,
    required this.topArtistsArtwork,
    required this.standardArtwork,
    required this.deluxeArtwork,
    required this.songArtwork,
  });

  final Database db;

  final Artist artist;
  final Album album;

  final AlbumEdition standardEdition;
  final AlbumEdition deluxeEdition;

  final Song alphaSong;
  final Song betaSong;
  final Song zuluSong;

  final ArtworkAsset artistHeaderArtwork;
  final ArtworkAsset topArtistsArtwork;
  final ArtworkAsset standardArtwork;
  final ArtworkAsset deluxeArtwork;
  final ArtworkAsset songArtwork;
}
