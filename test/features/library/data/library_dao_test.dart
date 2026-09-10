import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
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

  test('persists and loads complete library graph', () async {
    final db = await appDatabase.database;

    final artistDao = ArtistDao(db);
    final albumDao = AlbumDao(db);
    final editionDao = AlbumEditionDao(db);
    final songDao = SongDao(db);

    final createdAt = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_1',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final album = Album(
      id: 'album_1',
      artistId: artist.id,
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final edition = AlbumEdition(
      id: 'edition_1',
      albumId: album.id,
      title: 'Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final song = Song(
      id: 'song_1',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Track',
      canonicalTitle: 'track',
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await artistDao.insert(artist);
    await albumDao.insert(album);
    await editionDao.insert(edition);
    await songDao.insert(song);

    expect(await artistDao.findById(artist.id), artist);
    expect(await albumDao.findById(album.id), album);
    expect(await editionDao.findById(edition.id), edition);
    expect(await songDao.findById(song.id), song);

    expect(await albumDao.findByArtistId(artist.id), [album]);
    expect(await editionDao.findByAlbumId(album.id), [edition]);
    expect(await songDao.findByAlbumId(album.id), [song]);
    expect(await songDao.findByEditionId(edition.id), [song]);
  });

  test('updates entity without changing permanent identity', () async {
    final db = await appDatabase.database;
    final artistDao = ArtistDao(db);

    final createdAt = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_1',
      name: 'Original Name',
      canonicalName: 'original name',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await artistDao.insert(artist);

    final updated = artist.copyWith(
      name: 'Updated Name',
      canonicalName: 'updated name',
      updatedAt: DateTime.utc(2026, 9, 10, 13),
    );

    await artistDao.update(updated);

    final restored = await artistDao.findById(artist.id);

    expect(restored?.id, artist.id);
    expect(restored?.name, 'Updated Name');
    expect(restored?.canonicalName, 'updated name');
  });
}
