import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
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

  test('repositories persist and retrieve complete library graph', () async {
    final db = await appDatabase.database;

    final artistRepository = SqliteArtistRepository(ArtistDao(db));
    final albumRepository = SqliteAlbumRepository(AlbumDao(db));
    final editionRepository = SqliteAlbumEditionRepository(AlbumEditionDao(db));
    final songRepository = SqliteSongRepository(SongDao(db));

    final now = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_repo_1',
      name: 'Repository Artist',
      canonicalName: 'repository artist',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_repo_1',
      artistId: artist.id,
      title: 'Repository Album',
      canonicalTitle: 'repository album',
      createdAt: now,
      updatedAt: now,
    );

    final edition = AlbumEdition(
      id: 'edition_repo_1',
      albumId: album.id,
      title: 'Repository Album',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

    final song = Song(
      id: 'song_repo_1',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Repository Song',
      canonicalTitle: 'repository song',
      trackNumber: 1,
      durationSeconds: 210,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    await artistRepository.create(artist);
    await albumRepository.create(album);
    await editionRepository.create(edition);
    await songRepository.create(song);

    expect(await artistRepository.getById(artist.id), artist);
    expect(await albumRepository.getById(album.id), album);
    expect(await editionRepository.getById(edition.id), edition);
    expect(await songRepository.getById(song.id), song);

    expect(await albumRepository.getByArtistId(artist.id), [album]);
    expect(await editionRepository.getByAlbumId(album.id), [edition]);
    expect(await songRepository.getByArtistId(artist.id), [song]);
  });

  test('repository save preserves permanent entity identity', () async {
    final db = await appDatabase.database;

    final repository = SqliteArtistRepository(ArtistDao(db));
    final now = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_repo_save',
      name: 'Old Name',
      canonicalName: 'old name',
      createdAt: now,
      updatedAt: now,
    );

    await repository.create(artist);

    final renamed = artist.copyWith(
      name: 'New Name',
      canonicalName: 'new name',
      updatedAt: DateTime.utc(2026, 9, 10, 13),
    );

    await repository.save(renamed);

    final restored = await repository.getById(artist.id);

    expect(restored?.id, artist.id);
    expect(restored?.name, 'New Name');
    expect(restored?.canonicalName, 'new name');
  });
}
