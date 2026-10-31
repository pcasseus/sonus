import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/artwork/data/daos/artwork_asset_dao.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
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
    'track projection exposes explicit song block without hiding track',
    () async {
      final fixture = await _createFixture(appDatabase);

      await SongDao(fixture.db).update(
        fixture.alphaSong.copyWith(
          isBlocked: true,
          updatedAt: DateTime.utc(2026, 9, 26),
        ),
      );

      final tracks = await LibraryQueryDao(fixture.db).findTracks();

      final track = tracks.firstWhere(
        (candidate) => candidate.songId == fixture.alphaSong.id,
      );

      expect(track.isSongBlocked, isTrue);
      expect(track.isBlocked, isTrue);
      expect(tracks, hasLength(3));
    },
  );

  test(
    'legacy artist blacklist state does not block projected tracks',
    () async {
      final fixture = await _createFixture(appDatabase);

      await fixture.db.update(
        'artists',
        {'is_blacklisted': 1},
        where: 'id = ?',
        whereArgs: [fixture.artist.id],
      );

      final tracks = await LibraryQueryDao(fixture.db).findTracks();

      expect(tracks, hasLength(3));

      for (final track in tracks) {
        expect(track.isSongBlocked, isFalse);
        expect(track.isBlocked, isFalse);
      }
    },
  );

  test(
    'album query returns artist, primary edition metadata and track count',
    () async {
      final fixture = await _createFixture(appDatabase);
      await _list(fixture, fixture.standardEdition, [
        fixture.alphaSong,
        fixture.betaSong,
        fixture.zuluSong,
      ]);

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

  // SN-50 A-Q14A: a release card counts the tracks of the edition it shows
  // (the primary), not every song of every edition as before.
  test('album track count is the primary edition listing count, with all '
      'songs kept separately', () async {
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
    await _list(fixture, fixture.standardEdition, [
      fixture.alphaSong,
      fixture.betaSong,
    ]);
    await _list(fixture, fixture.deluxeEdition, [
      fixture.alphaSong,
      fixture.betaSong,
      fixture.zuluSong,
      deluxeSong,
    ]);

    final dao = LibraryQueryDao(fixture.db);
    final album = (await dao.findAlbums()).single;
    final lookedUp = (await dao.findAlbumById(fixture.album.id))!;

    expect(album.trackCount, 2);
    expect(lookedUp.trackCount, 2);
    expect(album.songCount, 4);
    expect(album.hasSongs, isTrue);
  });

  // SN-50 A-Q14B: the review judges the shown edition, so bonus songs on
  // another edition no longer hide a possible Single.
  test('possible-Single review uses the primary edition count', () async {
    final fixture = await _createFixture(appDatabase);
    final bonus = [
      for (final n in [1, 2])
        Song(
          id: 'song_bonus_$n',
          artistId: fixture.artist.id,
          albumId: fixture.album.id,
          albumEditionId: fixture.deluxeEdition.id,
          title: 'Bonus $n',
          canonicalTitle: 'bonus $n',
          trackNumber: 3 + n,
          durationSeconds: 200,
          isSingle: false,
          featuredArtists: const [],
          createdAt: DateTime.utc(2026, 9, 13),
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
    ];
    for (final song in bonus) {
      await SongDao(fixture.db).insert(song);
    }
    await _list(fixture, fixture.standardEdition, [
      fixture.alphaSong,
      fixture.betaSong,
      fixture.zuluSong,
    ]);
    await _list(fixture, fixture.deluxeEdition, [
      fixture.alphaSong,
      fixture.betaSong,
      fixture.zuluSong,
      ...bonus,
    ]);

    final albums = await LibraryQueryDao(fixture.db).findAlbums();

    // Three songs on the shown edition: it might be a Single, although the
    // release has five songs in all.
    expect(ArtistLibraryOrganization.formatReviewsOf(albums, const {}), {
      fixture.album.id,
    });
  });

  test('without a primary edition the card counts every song once', () async {
    final fixture = await _createFixture(appDatabase);
    await AlbumEditionDao(
      fixture.db,
    ).update(fixture.standardEdition.copyWith(isPrimary: false));

    final album = (await LibraryQueryDao(fixture.db).findAlbums()).single;

    expect(album.primaryEditionId, isNull);
    expect(album.trackCount, 3);
  });

  test('album song count spans editions, counting each song once', () async {
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

    expect(albums.single.songCount, 4);
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

  test('editions of a type are read across the library at once', () async {
    final fixture = await _createFixture(appDatabase);

    final deluxes = await LibraryQueryDao(
      fixture.db,
    ).findEditionsOfType(AlbumEditionType.deluxe);

    expect(deluxes, hasLength(1));
    expect(deluxes.single.editionId, fixture.deluxeEdition.id);
    expect(deluxes.single.albumId, fixture.album.id);
    expect(deluxes.single.type, AlbumEditionType.deluxe);
    expect(deluxes.single.releaseDate, DateTime.utc(2026, 6, 20));
  });

  test(
    'album edition query returns all editions with presentation metadata',
    () async {
      final fixture = await _createFixture(appDatabase);

      final editions = await LibraryQueryDao(
        fixture.db,
      ).findAlbumEditions(fixture.album.id);

      expect(editions, hasLength(2));

      expect(editions[0].editionId, fixture.standardEdition.id);
      expect(editions[0].albumId, fixture.album.id);
      expect(editions[0].title, 'Query Album');
      expect(editions[0].type, AlbumEditionType.standard);
      expect(editions[0].isPrimary, isTrue);
      expect(editions[0].releaseDate, DateTime.utc(2026, 1, 15));
      expect(editions[0].genre, 'Pop');

      expect(editions[1].editionId, fixture.deluxeEdition.id);
      expect(editions[1].title, 'Query Album Deluxe');
      expect(editions[1].type, AlbumEditionType.deluxe);
      expect(editions[1].isPrimary, isFalse);
      expect(editions[1].releaseDate, DateTime.utc(2026, 6, 20));
    },
  );

  test(
    'edition track query uses membership order and edition-specific placement',
    () async {
      final fixture = await _createFixture(appDatabase);
      final membershipDao = AlbumEditionTrackDao(fixture.db);
      final now = DateTime.utc(2026, 10, 1, 20);

      await membershipDao.insert(
        AlbumEditionTrack(
          albumEditionId: fixture.standardEdition.id,
          songId: fixture.alphaSong.id,
          discNumber: 1,
          trackNumber: 9,
          sortPosition: 10,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await membershipDao.insert(
        AlbumEditionTrack(
          albumEditionId: fixture.standardEdition.id,
          songId: fixture.betaSong.id,
          discNumber: 1,
          trackNumber: 4,
          sortPosition: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await membershipDao.insert(
        AlbumEditionTrack(
          albumEditionId: fixture.deluxeEdition.id,
          songId: fixture.alphaSong.id,
          discNumber: 2,
          trackNumber: 5,
          sortPosition: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final queryDao = LibraryQueryDao(fixture.db);

      final standard = await queryDao.findTracksByAlbumEditionId(
        fixture.standardEdition.id,
      );

      expect(standard.map((track) => track.songId), [
        fixture.betaSong.id,
        fixture.alphaSong.id,
      ]);

      expect(standard[0].albumEditionId, fixture.standardEdition.id);
      expect(standard[0].trackNumber, 4);
      expect(standard[0].discNumber, 1);

      expect(standard[1].trackNumber, 9);

      final deluxe = await queryDao.findTracksByAlbumEditionId(
        fixture.deluxeEdition.id,
      );

      expect(deluxe, hasLength(1));

      final sharedSong = deluxe.single;

      expect(sharedSong.songId, fixture.alphaSong.id);
      expect(sharedSong.albumEditionId, fixture.deluxeEdition.id);
      expect(sharedSong.albumEditionTitle, 'Query Album Deluxe');
      expect(sharedSong.albumEditionType, AlbumEditionType.deluxe);

      expect(sharedSong.discNumber, 2);
      expect(sharedSong.trackNumber, 5);

      // The permanent Song still points at its compatibility/default edition.
      expect(fixture.alphaSong.albumEditionId, fixture.standardEdition.id);
      expect(fixture.alphaSong.discNumber, 2);
      expect(fixture.alphaSong.trackNumber, 1);
    },
  );
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
      await _list(fixture, fixture.standardEdition, [
        fixture.alphaSong,
        fixture.betaSong,
        fixture.zuluSong,
      ]);

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
  // SN-50 C-Q1/C-Q6/C-Q9: track rows carry every credit role and search
  // finds version qualifiers the importer moved out of the title.
  group('role-aware credits and version search', () {
    Future<void> credit(
      Database db, {
      required String songId,
      required String name,
      required String role,
      required int position,
    }) {
      final timestamp = DateTime.utc(2026, 10, 29).toIso8601String();

      return db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_${songId}_$position',
        'song_id': songId,
        'artist_id': null,
        'credited_name': name,
        'canonical_credited_name': name.toLowerCase(),
        'role': role,
        'position': position,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
    }

    test(
      'track rows list co-primary and guest names in credit order',
      () async {
        final fixture = await _createFixture(appDatabase);
        final db = fixture.db;
        final songId = fixture.alphaSong.id;

        await credit(
          db,
          songId: songId,
          name: 'Guest Two',
          role: 'guest',
          position: 4,
        );
        await credit(
          db,
          songId: songId,
          name: 'Crane, The Lantern',
          role: 'coPrimary',
          position: 2,
        );
        await credit(
          db,
          songId: songId,
          name: 'Guest One',
          role: 'guest',
          position: 3,
        );
        await credit(
          db,
          songId: songId,
          name: 'Ben Moor',
          role: 'coPrimary',
          position: 1,
        );
        await credit(
          db,
          songId: songId,
          name: 'Featured Artist',
          role: 'featured',
          position: 5,
        );

        final dao = LibraryQueryDao(db);
        final fromList = (await dao.findTracks()).firstWhere(
          (track) => track.songId == songId,
        );
        final byId = await dao.findTrackById(songId);
        final byAlbum = (await dao.findTracksByAlbumId(
          fixture.album.id,
        )).firstWhere((track) => track.songId == songId);

        for (final track in [fromList, byId!, byAlbum]) {
          expect(track.coPrimaryArtists, ['Ben Moor', 'Crane, The Lantern']);
          expect(track.guestArtists, ['Guest One', 'Guest Two']);
          expect(
            track.creditLine,
            'Query Artist & Ben Moor & Crane, The Lantern Ft. Featured Artist '
            'with Guest One, Guest Two',
          );
        }

        final beta = (await dao.findTracks()).firstWhere(
          (track) => track.songId == fixture.betaSong.id,
        );
        expect(beta.coPrimaryArtists, isEmpty);
        expect(beta.guestArtists, isEmpty);
      },
    );

    test('SN-50 project song credits keep linked and unlinked credits, '
        'including songs listed only on an edition', () async {
      final fixture = await _createFixture(appDatabase);
      final db = fixture.db;
      final timestamp = DateTime.utc(2026, 10, 29);
      await AlbumDao(db).insert(
        Album(
          id: 'album_elsewhere',
          artistId: fixture.artist.id,
          title: 'Elsewhere',
          canonicalTitle: 'elsewhere',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await AlbumEditionDao(db).insert(
        AlbumEdition(
          id: 'edition_elsewhere',
          albumId: 'album_elsewhere',
          title: 'Elsewhere',
          type: AlbumEditionType.standard,
          isPrimary: true,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await SongDao(db).insert(
        Song(
          id: 'song_bonus',
          artistId: fixture.artist.id,
          albumId: 'album_elsewhere',
          albumEditionId: 'edition_elsewhere',
          title: 'Bonus Track',
          canonicalTitle: 'bonus track',
          trackNumber: 1,
          durationSeconds: 120,
          isSingle: false,
          featuredArtists: const [],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await _listIn(db, fixture.deluxeEdition.id, ['song_bonus']);
      await db.insert(DatabaseTables.songArtistCredits, {
        'id': 'credit_linked',
        'song_id': fixture.alphaSong.id,
        'artist_id': fixture.artist.id,
        'credited_name': 'Query Artist',
        'canonical_credited_name': 'query artist',
        'role': 'primary',
        'position': 0,
        'created_at': timestamp.toIso8601String(),
        'updated_at': timestamp.toIso8601String(),
      });
      await credit(
        db,
        songId: fixture.alphaSong.id,
        name: 'Unlinked Guest',
        role: 'guest',
        position: 1,
      );
      await credit(
        db,
        songId: 'song_bonus',
        name: 'Bonus Feature',
        role: 'featured',
        position: 0,
      );

      final credits = await LibraryQueryDao(
        db,
      ).findProjectSongCredits(fixture.album.id);

      expect(
        [
          for (final c in credits)
            (c.albumId, c.songId, c.artistId, c.creditedName, c.role.name),
        ],
        [
          (
            fixture.album.id,
            'song_alpha',
            fixture.artist.id,
            'Query Artist',
            'primary',
          ),
          (fixture.album.id, 'song_alpha', null, 'Unlinked Guest', 'guest'),
          (fixture.album.id, 'song_bonus', null, 'Bonus Feature', 'featured'),
        ],
      );
      expect(
        await LibraryQueryDao(db).findProjectSongCredits('album_elsewhere'),
        hasLength(1),
      );
    });

    test('search matches version labels, characteristics and every credit '
        'role', () async {
      final fixture = await _createFixture(appDatabase);
      final db = fixture.db;

      await db.update(
        DatabaseTables.songs,
        {'version_label': 'Live', 'version_characteristics': '["live"]'},
        where: 'id = ?',
        whereArgs: [fixture.betaSong.id],
      );
      await db.update(
        DatabaseTables.songs,
        {'version_characteristics': '["remix","acoustic"]'},
        where: 'id = ?',
        whereArgs: [fixture.zuluSong.id],
      );
      await credit(
        db,
        songId: fixture.alphaSong.id,
        name: 'Lantern Guest',
        role: 'guest',
        position: 1,
      );

      final dao = LibraryQueryDao(db);
      Future<List<String>> songIds(String query) async => (await dao.search(
        query,
      )).tracks.map((track) => track.songId).toList();

      expect(await songIds('live'), [fixture.betaSong.id]);
      expect(await songIds('beta track (live'), [fixture.betaSong.id]);
      expect(await songIds('acoustic remix'), [fixture.zuluSong.id]);
      expect(await songIds('lantern guest'), [fixture.alphaSong.id]);

      final beta = (await dao.findTrackById(fixture.betaSong.id))!;
      expect(beta.title, 'Beta Track');
      expect(beta.displayTitle, 'Beta Track (Live)');
    });
  });

  // SN-50 A-Q3: the shown release title is the primary edition's; the
  // stored base title stays what charts, history and import matching use.
  group('displayed release title', () {
    test('follows the primary edition and keeps the base title', () async {
      final fixture = await _createFixture(appDatabase);
      await AlbumEditionDao(fixture.db).update(
        fixture.standardEdition.copyWith(title: 'Query Album (Night Cut)'),
      );
      final dao = LibraryQueryDao(fixture.db);

      final album = (await dao.findAlbums()).single;
      final lookedUp = (await dao.findAlbumById(fixture.album.id))!;
      final track = (await dao.findTrackById(fixture.alphaSong.id))!;
      final listed = (await dao.findTracks()).firstWhere(
        (track) => track.songId == fixture.alphaSong.id,
      );

      expect(album.title, 'Query Album');
      expect(album.displayTitle, 'Query Album (Night Cut)');
      expect(lookedUp.displayTitle, 'Query Album (Night Cut)');
      expect(track.albumTitle, 'Query Album');
      expect(track.albumDisplayTitle, 'Query Album (Night Cut)');
      expect(listed.albumDisplayTitle, 'Query Album (Night Cut)');
    });

    test('switches with the primary edition', () async {
      final fixture = await _createFixture(appDatabase);
      final editions = AlbumEditionDao(fixture.db);
      await editions.update(fixture.standardEdition.copyWith(isPrimary: false));
      await editions.update(fixture.deluxeEdition.copyWith(isPrimary: true));

      final dao = LibraryQueryDao(fixture.db);

      expect(
        (await dao.findAlbums()).single.displayTitle,
        'Query Album Deluxe',
      );
      expect(
        (await dao.findTrackById(fixture.betaSong.id))!.albumDisplayTitle,
        'Query Album Deluxe',
      );
    });

    test('a type-only edition name shows the base title', () async {
      final fixture = await _createFixture(appDatabase);
      await AlbumEditionDao(
        fixture.db,
      ).update(fixture.standardEdition.copyWith(title: 'Standard'));

      final album = (await LibraryQueryDao(fixture.db).findAlbums()).single;

      expect(album.displayTitle, 'Query Album');
    });

    test('search finds the release by base and by shown title', () async {
      final fixture = await _createFixture(appDatabase);
      await AlbumEditionDao(fixture.db).update(
        fixture.standardEdition.copyWith(title: 'Query Album (Night Cut)'),
      );
      final dao = LibraryQueryDao(fixture.db);

      for (final query in ['query album', 'night cut']) {
        final results = await dao.search(query);
        expect(results.albums.map((album) => album.albumId), [
          fixture.album.id,
        ], reason: query);
      }
      expect(
        (await dao.search('night cut')).tracks.map((track) => track.songId),
        contains(fixture.alphaSong.id),
      );
    });
  });

  // SN-50 A-Q12: outside an edition view a song shows its own artwork, then
  // the primary cover if it is on the primary edition, then its home
  // edition's cover, then the primary cover.
  group('song artwork outside an edition view', () {
    Song deluxeHomed(_ArtworkQueryFixture fixture, String id) => Song(
      id: id,
      artistId: fixture.artist.id,
      albumId: fixture.album.id,
      albumEditionId: fixture.deluxeEdition.id,
      title: 'Track $id',
      canonicalTitle: 'track $id',
      trackNumber: 4,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    test('a song homed on Deluxe but on the primary shows the primary '
        'cover', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final song = deluxeHomed(fixture, 'song_shared');
      await SongDao(fixture.db).insert(song);
      await _listIn(fixture.db, fixture.standardEdition.id, [song.id]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song.id]);
      final dao = LibraryQueryDao(fixture.db);

      final track = (await dao.findTrackById(song.id))!;
      final listed = (await dao.findTracksByAlbumId(
        fixture.album.id,
      )).firstWhere((track) => track.songId == song.id);

      expect(track.artworkId, fixture.standardArtwork.id);
      expect(track.artworkPath, fixture.standardArtwork.filePath);
      expect(listed.artworkId, fixture.standardArtwork.id);
    });

    test('a Deluxe-only song keeps the Deluxe cover', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final song = deluxeHomed(fixture, 'song_bonus');
      await SongDao(fixture.db).insert(song);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song.id]);

      final track = (await LibraryQueryDao(fixture.db).findTrackById(song.id))!;

      expect(track.artworkId, fixture.deluxeArtwork.id);
    });

    test('a song homed on an edition without a cover shows the primary '
        'cover, there and in that edition', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final bare = AlbumEdition(
        id: 'edition_bare',
        albumId: fixture.album.id,
        title: 'Query Album (Tour Cut)',
        type: AlbumEditionType.other,
        isPrimary: false,
        createdAt: DateTime.utc(2026, 9, 16),
        updatedAt: DateTime.utc(2026, 9, 16),
      );
      await AlbumEditionDao(fixture.db).insert(bare);
      final song = deluxeHomed(
        fixture,
        'song_tour',
      ).copyWith(albumEditionId: bare.id);
      await SongDao(fixture.db).insert(song);
      await _listIn(fixture.db, bare.id, [song.id]);
      final dao = LibraryQueryDao(fixture.db);

      final track = (await dao.findTrackById(song.id))!;
      final inEdition = (await dao.findTracksByAlbumEditionId(bare.id)).single;

      expect(track.artworkId, fixture.standardArtwork.id);
      expect(inEdition.artworkId, fixture.standardArtwork.id);
    });

    test('song artwork still comes first', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      await _listIn(fixture.db, fixture.standardEdition.id, [
        fixture.alphaSong.id,
      ]);

      final track = (await LibraryQueryDao(
        fixture.db,
      ).findTrackById(fixture.alphaSong.id))!;

      expect(track.artworkId, fixture.songArtwork.id);
    });
  });

  // SN-50 A-Q13: when the primary edition has no cover, the release and the
  // songs that fall back to it show the placeholder, never another edition's
  // cover.
  group('a primary edition without a cover', () {
    Future<_ArtworkQueryFixture> uncoveredPrimary() async {
      final fixture = await _createArtworkFixture(appDatabase);
      await fixture.db.update(
        DatabaseTables.albumEditions,
        {'artwork_id': null},
        where: 'id = ?',
        whereArgs: [fixture.standardEdition.id],
      );
      return fixture;
    }

    test('release cards and the album show the placeholder', () async {
      final fixture = await uncoveredPrimary();
      final dao = LibraryQueryDao(fixture.db);

      final card = (await dao.findAlbums()).singleWhere(
        (album) => album.albumId == fixture.album.id,
      );
      final album = (await dao.findAlbumById(fixture.album.id))!;
      final byArtist = (await dao.findAlbumsByArtistId(
        fixture.artist.id,
      )).single;

      expect(card.artworkId, isNull);
      expect(card.artworkPath, isNull);
      expect(album.artworkPath, isNull);
      expect(byArtist.artworkPath, isNull);
    });

    test('a Deluxe-homed song listed on the primary shows the placeholder, '
        'not the Deluxe cover', () async {
      final fixture = await uncoveredPrimary();
      final song = Song(
        id: 'song_shared',
        artistId: fixture.artist.id,
        albumId: fixture.album.id,
        albumEditionId: fixture.deluxeEdition.id,
        title: 'Shared',
        canonicalTitle: 'shared',
        trackNumber: 4,
        durationSeconds: 200,
        isSingle: false,
        featuredArtists: const [],
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      );
      await SongDao(fixture.db).insert(song);
      await _listIn(fixture.db, fixture.standardEdition.id, [song.id]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song.id]);
      final dao = LibraryQueryDao(fixture.db);

      final track = (await dao.findTrackById(song.id))!;
      final listed = (await dao.findTracks()).singleWhere(
        (track) => track.songId == song.id,
      );
      final inPrimary = (await dao.findTracksByAlbumEditionId(
        fixture.standardEdition.id,
      )).singleWhere((track) => track.songId == song.id);

      expect(track.artworkId, isNull);
      expect(track.artworkPath, isNull);
      expect(listed.artworkId, isNull);
      expect(inPrimary.artworkId, isNull);
    });

    test('a song with its own artwork keeps it', () async {
      final fixture = await uncoveredPrimary();
      await _listIn(fixture.db, fixture.standardEdition.id, [
        fixture.alphaSong.id,
      ]);

      final track = (await LibraryQueryDao(
        fixture.db,
      ).findTrackById(fixture.alphaSong.id))!;

      expect(track.artworkId, fixture.songArtwork.id);
    });
  });

  // SN-50 A-Q12 (decided 2026-10-31): inside an edition view a song shows
  // the selected edition's cover, then its own artwork, then the primary
  // edition's cover, then the placeholder. Never another non-primary
  // edition's cover.
  group('song artwork inside an edition view', () {
    Future<AlbumEdition> bareEdition(_ArtworkQueryFixture fixture) async {
      final bare = AlbumEdition(
        id: 'edition_bare',
        albumId: fixture.album.id,
        title: 'Query Album (Tour Cut)',
        type: AlbumEditionType.other,
        isPrimary: false,
        createdAt: DateTime.utc(2026, 9, 16),
        updatedAt: DateTime.utc(2026, 9, 16),
      );
      await AlbumEditionDao(fixture.db).insert(bare);
      return bare;
    }

    Future<String?> artworkIn(
      _ArtworkQueryFixture fixture,
      String editionId,
      String songId,
    ) async => (await LibraryQueryDao(fixture.db).findTracksByAlbumEditionId(
      editionId,
    )).singleWhere((track) => track.songId == songId).artworkId;

    test("the selected edition's cover wins over the song's own "
        "artwork", () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final song = fixture.alphaSong.id;
      await _listIn(fixture.db, fixture.standardEdition.id, [song]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song]);

      expect(
        await artworkIn(fixture, fixture.standardEdition.id, song),
        fixture.standardArtwork.id,
      );
      expect(
        await artworkIn(fixture, fixture.deluxeEdition.id, song),
        fixture.deluxeArtwork.id,
      );
    });

    test("in an edition without a cover the song's own artwork comes "
        "before the primary cover", () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final bare = await bareEdition(fixture);
      final song = fixture.alphaSong.id;
      await _listIn(fixture.db, fixture.standardEdition.id, [song]);
      await _listIn(fixture.db, bare.id, [song]);

      expect(await artworkIn(fixture, bare.id, song), fixture.songArtwork.id);
    });

    test("outside an edition view the song's own artwork still "
        "wins", () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final song = fixture.alphaSong.id;
      await _listIn(fixture.db, fixture.standardEdition.id, [song]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song]);

      final tracks = await LibraryQueryDao(fixture.db).findTracks();
      expect(
        tracks.singleWhere((track) => track.songId == song).artworkId,
        fixture.songArtwork.id,
      );
    });

    test("without its own artwork a song shows the selected edition's "
        "cover", () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final song = fixture.betaSong.id;
      await _listIn(fixture.db, fixture.standardEdition.id, [song]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [song]);

      expect(
        await artworkIn(fixture, fixture.standardEdition.id, song),
        fixture.standardArtwork.id,
      );
      expect(
        await artworkIn(fixture, fixture.deluxeEdition.id, song),
        fixture.deluxeArtwork.id,
      );
    });

    test('a Deluxe-only song shows the Deluxe cover, not the '
        'Standard', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      await SongDao(fixture.db).update(
        fixture.zuluSong.copyWith(albumEditionId: fixture.deluxeEdition.id),
      );
      await _listIn(fixture.db, fixture.deluxeEdition.id, [
        fixture.zuluSong.id,
      ]);

      expect(
        await artworkIn(fixture, fixture.deluxeEdition.id, fixture.zuluSong.id),
        fixture.deluxeArtwork.id,
      );
    });

    test("an edition without a cover falls back to the primary cover, "
        "never another edition's", () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final bare = await bareEdition(fixture);
      await SongDao(fixture.db).update(
        fixture.zuluSong.copyWith(albumEditionId: fixture.deluxeEdition.id),
      );
      await _listIn(fixture.db, fixture.deluxeEdition.id, [
        fixture.zuluSong.id,
      ]);
      await _listIn(fixture.db, bare.id, [fixture.zuluSong.id]);

      expect(
        await artworkIn(fixture, bare.id, fixture.zuluSong.id),
        fixture.standardArtwork.id,
      );
    });

    test('with no primary cover either, the placeholder shows', () async {
      final fixture = await _createArtworkFixture(appDatabase);
      final bare = await bareEdition(fixture);
      await fixture.db.update(
        DatabaseTables.albumEditions,
        {'artwork_id': null},
        where: 'id = ?',
        whereArgs: [fixture.standardEdition.id],
      );
      await _listIn(fixture.db, bare.id, [fixture.betaSong.id]);
      await _listIn(fixture.db, fixture.deluxeEdition.id, [
        fixture.betaSong.id,
      ]);

      final track = (await LibraryQueryDao(
        fixture.db,
      ).findTracksByAlbumEditionId(bare.id)).single;

      expect(track.artworkId, isNull);
      expect(track.artworkPath, isNull);
    });
  });
}

/// Lists [songIds] on [editionId], numbered in the order given.
Future<void> _listIn(
  DatabaseExecutor db,
  String editionId,
  List<String> songIds,
) async {
  final dao = AlbumEditionTrackDao(db);
  final now = DateTime.utc(2026, 10, 1);
  for (final (index, songId) in songIds.indexed) {
    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: editionId,
        songId: songId,
        discNumber: 1,
        trackNumber: index + 1,
        sortPosition: index,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Lists [songs] on [edition], numbered in the order given.
Future<void> _list(
  _QueryFixture fixture,
  AlbumEdition edition,
  List<Song> songs,
) async {
  final dao = AlbumEditionTrackDao(fixture.db);
  final now = DateTime.utc(2026, 10, 1);
  for (final (index, song) in songs.indexed) {
    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: edition.id,
        songId: song.id,
        discNumber: 1,
        trackNumber: index + 1,
        sortPosition: index,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
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
