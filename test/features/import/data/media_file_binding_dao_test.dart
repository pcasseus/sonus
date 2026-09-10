import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
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

  test('moving a file updates binding but preserves song identity', () async {
    final db = await appDatabase.database;

    final artistDao = ArtistDao(db);
    final albumDao = AlbumDao(db);
    final editionDao = AlbumEditionDao(db);
    final songDao = SongDao(db);
    final bindingDao = MediaFileBindingDao(db);

    final now = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_1',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_1',
      artistId: artist.id,
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: now,
      updatedAt: now,
    );

    final edition = AlbumEdition(
      id: 'edition_1',
      albumId: album.id,
      title: 'Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final song = Song(
      id: 'song_1',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Track',
      canonicalTitle: 'track',
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    await artistDao.insert(artist);
    await albumDao.insert(album);
    await editionDao.insert(edition);
    await songDao.insert(song);

    final binding = MediaFileBinding(
      id: 'media_1',
      songId: song.id,
      filePath: r'C:\Music\Artist\Album\Track.mp3',
      normalizedPath: 'c:/music/artist/album/track.mp3',
      isAvailable: true,
      lastSeenAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await bindingDao.insert(binding);

    final moved = binding.copyWith(
      filePath: r'D:\Music\Artist\Album\Track.mp3',
      normalizedPath: 'd:/music/artist/album/track.mp3',
      updatedAt: DateTime.utc(2026, 9, 10, 13),
    );

    await bindingDao.update(moved);

    final restoredBinding = await bindingDao.findById(binding.id);
    final restoredSong = await songDao.findById(song.id);

    expect(restoredBinding?.id, binding.id);
    expect(restoredBinding?.songId, song.id);
    expect(restoredBinding?.normalizedPath, 'd:/music/artist/album/track.mp3');

    expect(restoredSong?.id, song.id);
    expect(restoredSong, song);
  });
}
