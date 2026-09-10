import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
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

  test('media repository keeps file location separate from song', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_media_repo',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_media_repo',
      artistId: artist.id,
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: now,
      updatedAt: now,
    );

    final edition = AlbumEdition(
      id: 'edition_media_repo',
      albumId: album.id,
      title: 'Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final song = Song(
      id: 'song_media_repo',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Track',
      canonicalTitle: 'track',
      trackNumber: 1,
      durationSeconds: 190,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);

    final repository = SqliteMediaFileBindingRepository(
      MediaFileBindingDao(db),
    );

    final binding = MediaFileBinding(
      id: 'media_repo_1',
      songId: song.id,
      filePath: r'C:\Music\Track.mp3',
      normalizedPath: 'c:/music/track.mp3',
      isAvailable: true,
      lastSeenAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await repository.create(binding);

    expect(await repository.getById(binding.id), binding);
    expect(
      await repository.getByNormalizedPath(binding.normalizedPath),
      binding,
    );
    expect(await repository.getBySongId(song.id), [binding]);
  });
}
