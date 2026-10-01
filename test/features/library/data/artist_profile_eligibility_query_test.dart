import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/daos/library_query_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late SqliteLibraryQueryRepository repository;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    db = await appDatabase.database;

    repository = SqliteLibraryQueryRepository(LibraryQueryDao(db));
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'feature-only Artist identity is stored but not profile eligible',
    () async {
      await _insertArtist(db, id: 'primary_artist', name: 'Primary Artist');

      await _insertArtist(db, id: 'feature_artist', name: 'Feature Artist');

      await _insertAlbumStructure(
        db,
        artistId: 'primary_artist',
        albumId: 'album_1',
        editionId: 'edition_1',
      );

      await _insertSong(
        db,
        id: 'song_1',
        artistId: 'primary_artist',
        albumId: 'album_1',
        editionId: 'edition_1',
        title: 'Feature Song',
      );

      await _insertCredit(
        db,
        id: 'credit_primary',
        songId: 'song_1',
        artistId: 'primary_artist',
        creditedName: 'Primary Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_feature',
        songId: 'song_1',
        artistId: 'feature_artist',
        creditedName: 'Feature Artist',
        role: 'featured',
        position: 1,
      );

      final artists = await repository.getArtists();
      final profileEligibleArtists = await repository
          .getProfileEligibleArtists();

      expect(
        artists.map((artist) => artist.artistId),
        containsAll(['primary_artist', 'feature_artist']),
      );

      expect(
        profileEligibleArtists.map((artist) => artist.artistId),
        contains('primary_artist'),
      );

      expect(
        profileEligibleArtists.map((artist) => artist.artistId),
        isNot(contains('feature_artist')),
      );

      expect(await repository.getArtistById('feature_artist'), isNotNull);

      expect(
        await repository.getProfileEligibleArtistById('feature_artist'),
        isNull,
      );
      final identityRows = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['feature_artist'],
      );

      expect(identityRows, hasLength(1));
    },
  );

  test('co-primary credit alone makes Artist profile eligible', () async {
    await _insertArtist(db, id: 'primary_artist', name: 'Primary Artist');

    await _insertArtist(db, id: 'co_primary_artist', name: 'Co Primary Artist');

    await _insertAlbumStructure(
      db,
      artistId: 'primary_artist',
      albumId: 'album_1',
      editionId: 'edition_1',
    );

    await _insertSong(
      db,
      id: 'song_1',
      artistId: 'primary_artist',
      albumId: 'album_1',
      editionId: 'edition_1',
      title: 'Joint Song',
    );

    await _insertCredit(
      db,
      id: 'credit_primary',
      songId: 'song_1',
      artistId: 'primary_artist',
      creditedName: 'Primary Artist',
      role: 'primary',
      position: 0,
    );

    await _insertCredit(
      db,
      id: 'credit_co_primary',
      songId: 'song_1',
      artistId: 'co_primary_artist',
      creditedName: 'Co Primary Artist',
      role: 'coPrimary',
      position: 1,
    );

    final artist = await repository.getProfileEligibleArtistById(
      'co_primary_artist',
    );

    expect(artist, isNotNull);
    expect(artist!.songCount, 1);
    expect(artist.albumCount, 0);

    final mainTracks = await repository.getMainTracksByArtistId(
      'co_primary_artist',
    );

    final collaborations = await repository.getCollaborationTracksByArtistId(
      'co_primary_artist',
    );

    expect(mainTracks.map((track) => track.songId), ['song_1']);

    expect(collaborations, isEmpty);
  });

  test(
    'featured and guest credits populate Collaborations but co-primary stays main',
    () async {
      await _insertArtist(db, id: 'profile_artist', name: 'Profile Artist');

      await _insertArtist(db, id: 'other_artist', name: 'Other Artist');

      await _insertAlbumStructure(
        db,
        artistId: 'profile_artist',
        albumId: 'profile_album',
        editionId: 'profile_edition',
      );

      await _insertAlbumStructure(
        db,
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
      );

      await _insertSong(
        db,
        id: 'primary_song',
        artistId: 'profile_artist',
        albumId: 'profile_album',
        editionId: 'profile_edition',
        title: 'Primary Song',
      );

      await _insertSong(
        db,
        id: 'co_primary_song',
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
        title: 'Joint Song',
      );

      await _insertSong(
        db,
        id: 'feature_song',
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
        title: 'Feature Song',
        trackNumber: 2,
      );

      await _insertSong(
        db,
        id: 'guest_song',
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
        title: 'Guest Song',
        trackNumber: 3,
      );

      await _insertCredit(
        db,
        id: 'credit_primary_song',
        songId: 'primary_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_other_joint',
        songId: 'co_primary_song',
        artistId: 'other_artist',
        creditedName: 'Other Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_profile_joint',
        songId: 'co_primary_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'coPrimary',
        position: 1,
      );

      await _insertCredit(
        db,
        id: 'credit_other_feature',
        songId: 'feature_song',
        artistId: 'other_artist',
        creditedName: 'Other Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_profile_feature',
        songId: 'feature_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'featured',
        position: 1,
      );

      await _insertCredit(
        db,
        id: 'credit_other_guest',
        songId: 'guest_song',
        artistId: 'other_artist',
        creditedName: 'Other Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_profile_guest',
        songId: 'guest_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'guest',
        position: 1,
      );

      final mainTracks = await repository.getMainTracksByArtistId(
        'profile_artist',
      );

      final collaborations = await repository.getCollaborationTracksByArtistId(
        'profile_artist',
      );

      expect(mainTracks.map((track) => track.songId).toSet(), {
        'primary_song',
        'co_primary_song',
      });

      expect(collaborations.map((track) => track.songId).toSet(), {
        'feature_song',
        'guest_song',
      });

      expect(
        collaborations.map((track) => track.songId),
        isNot(contains('co_primary_song')),
      );
    },
  );

  test(
    'losing last primary or co-primary credit hides profile without deleting identity',
    () async {
      await _insertArtist(db, id: 'artist_1', name: 'Artist One');

      await _insertAlbumStructure(
        db,
        artistId: 'artist_1',
        albumId: 'album_1',
        editionId: 'edition_1',
      );

      await _insertSong(
        db,
        id: 'song_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        editionId: 'edition_1',
        title: 'Only Song',
      );

      await _insertCredit(
        db,
        id: 'credit_1',
        songId: 'song_1',
        artistId: 'artist_1',
        creditedName: 'Artist One',
        role: 'primary',
        position: 0,
      );

      expect(
        await repository.getProfileEligibleArtistById('artist_1'),
        isNotNull,
      );

      await db.delete(
        DatabaseTables.songArtistCredits,
        where: 'id = ?',
        whereArgs: ['credit_1'],
      );

      expect(await repository.getProfileEligibleArtistById('artist_1'), isNull);

      final identityRows = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_1'],
      );

      expect(identityRows, hasLength(1));
    },
  );

  test(
    'ArtistProfileController uses structured main and collaboration membership',
    () async {
      await _insertArtist(db, id: 'profile_artist', name: 'Profile Artist');

      await _insertArtist(db, id: 'other_artist', name: 'Other Artist');

      await _insertAlbumStructure(
        db,
        artistId: 'profile_artist',
        albumId: 'profile_album',
        editionId: 'profile_edition',
      );

      await _insertAlbumStructure(
        db,
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
      );

      await _insertSong(
        db,
        id: 'main_song',
        artistId: 'profile_artist',
        albumId: 'profile_album',
        editionId: 'profile_edition',
        title: 'Main Song',
      );

      await _insertSong(
        db,
        id: 'feature_song',
        artistId: 'other_artist',
        albumId: 'other_album',
        editionId: 'other_edition',
        title: 'Feature Song',
      );

      await _insertCredit(
        db,
        id: 'credit_main',
        songId: 'main_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_other',
        songId: 'feature_song',
        artistId: 'other_artist',
        creditedName: 'Other Artist',
        role: 'primary',
        position: 0,
      );

      await _insertCredit(
        db,
        id: 'credit_feature',
        songId: 'feature_song',
        artistId: 'profile_artist',
        creditedName: 'Profile Artist',
        role: 'featured',
        position: 1,
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'profile_artist',
      );

      await controller.load();

      expect(controller.isNotFound, isFalse);

      expect(controller.tracks.map((track) => track.songId), ['main_song']);

      expect(controller.featuredTracks.map((track) => track.songId), [
        'feature_song',
      ]);

      expect(controller.allTracks.map((track) => track.songId).toSet(), {
        'main_song',
        'feature_song',
      });

      controller.dispose();
    },
  );
}

Future<void> _insertArtist(
  Database db, {
  required String id,
  required String name,
}) {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  return db.insert(DatabaseTables.artists, {
    'id': id,
    'name': name,
    'canonical_name': name.toLowerCase(),
    'header_artwork_id': null,
    'top_artists_artwork_id': null,
    'is_blacklisted': 0,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<void> _insertAlbumStructure(
  Database db, {
  required String artistId,
  required String albumId,
  required String editionId,
}) async {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  await db.insert(DatabaseTables.albums, {
    'id': albumId,
    'artist_id': artistId,
    'title': '$albumId title',
    'canonical_title': '$albumId title',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': editionId,
    'album_id': albumId,
    'title': '$albumId title',
    'type': 'standard',
    'is_primary': 1,
    'release_date': null,
    'genre': null,
    'artwork_id': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<void> _insertSong(
  Database db, {
  required String id,
  required String artistId,
  required String albumId,
  required String editionId,
  required String title,
  int trackNumber = 1,
}) {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  return db.insert(DatabaseTables.songs, {
    'id': id,
    'artist_id': artistId,
    'album_id': albumId,
    'album_edition_id': editionId,
    'title': title,
    'canonical_title': title.toLowerCase(),
    'track_number': trackNumber,
    'disc_number': 1,
    'duration_seconds': 180,
    'is_single': 0,
    'is_blocked': 0,
    'featured_artists': '[]',
    'artwork_id': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<void> _insertCredit(
  Database db, {
  required String id,
  required String songId,
  required String artistId,
  required String creditedName,
  required String role,
  required int position,
}) {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  return db.insert(DatabaseTables.songArtistCredits, {
    'id': id,
    'song_id': songId,
    'artist_id': artistId,
    'credited_name': creditedName,
    'canonical_credited_name': creditedName.toLowerCase(),
    'role': role,
    'position': position,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}
