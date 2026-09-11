import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_repository.dart';
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

  test(
    'album repository returns every album in deterministic title order',
    () async {
      final db = await appDatabase.database;

      final artist = Artist(
        id: 'artist_query',
        name: 'Query Artist',
        canonicalName: 'query artist',
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      );

      await ArtistDao(db).insert(artist);

      final repository = SqliteAlbumRepository(AlbumDao(db));

      await repository.create(
        Album(
          id: 'album_z',
          artistId: artist.id,
          title: 'Zulu',
          canonicalTitle: 'zulu',
          createdAt: DateTime.utc(2026, 9, 10),
          updatedAt: DateTime.utc(2026, 9, 10),
        ),
      );

      await repository.create(
        Album(
          id: 'album_a',
          artistId: artist.id,
          title: 'Alpha',
          canonicalTitle: 'alpha',
          createdAt: DateTime.utc(2026, 9, 11),
          updatedAt: DateTime.utc(2026, 9, 11),
        ),
      );

      final albums = await repository.getAll();

      expect(albums.map((album) => album.id).toList(), ['album_a', 'album_z']);
    },
  );

  test('album repository returns newest albums first with a limit', () async {
    final db = await appDatabase.database;

    final artist = Artist(
      id: 'artist_recent_album',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    );

    await ArtistDao(db).insert(artist);

    final repository = SqliteAlbumRepository(AlbumDao(db));

    for (var index = 1; index <= 3; index++) {
      await repository.create(
        Album(
          id: 'album_$index',
          artistId: artist.id,
          title: 'Album $index',
          canonicalTitle: 'album $index',
          createdAt: DateTime.utc(2026, 9, 10 + index),
          updatedAt: DateTime.utc(2026, 9, 10 + index),
        ),
      );
    }

    final recent = await repository.getRecentlyAdded(2);

    expect(recent.map((album) => album.id).toList(), ['album_3', 'album_2']);

    expect(await repository.getRecentlyAdded(0), isEmpty);
  });

  test('edition repository can enumerate editions', () async {
    final db = await appDatabase.database;

    final artist = Artist(
      id: 'artist_editions',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    );

    final album = Album(
      id: 'album_editions',
      artistId: artist.id,
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    );

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);

    final repository = SqliteAlbumEditionRepository(AlbumEditionDao(db));

    await repository.create(
      AlbumEdition(
        id: 'edition_deluxe',
        albumId: album.id,
        title: 'Album Deluxe',
        type: AlbumEditionType.deluxe,
        isPrimary: false,
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      ),
    );

    await repository.create(
      AlbumEdition(
        id: 'edition_standard',
        albumId: album.id,
        title: 'Album',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      ),
    );

    final editions = await repository.getAll();

    expect(editions.map((edition) => edition.id).toSet(), {
      'edition_standard',
      'edition_deluxe',
    });
  });

  test('song repository returns all songs in title order', () async {
    final graph = await _createLibraryGraph(appDatabase);

    final repository = SqliteSongRepository(SongDao(graph.db));

    await repository.create(
      _song(
        id: 'song_z',
        title: 'Zulu',
        graph: graph,
        createdAt: DateTime.utc(2026, 9, 10),
      ),
    );

    await repository.create(
      _song(
        id: 'song_a',
        title: 'Alpha',
        graph: graph,
        createdAt: DateTime.utc(2026, 9, 11),
      ),
    );

    final songs = await repository.getAll();

    expect(songs.map((song) => song.id).toList(), ['song_a', 'song_z']);
  });

  test('song repository returns newest songs first with a limit', () async {
    final graph = await _createLibraryGraph(appDatabase);

    final repository = SqliteSongRepository(SongDao(graph.db));

    for (var index = 1; index <= 3; index++) {
      await repository.create(
        _song(
          id: 'song_$index',
          title: 'Song $index',
          graph: graph,
          createdAt: DateTime.utc(2026, 9, 10 + index),
        ),
      );
    }

    final recent = await repository.getRecentlyAdded(2);

    expect(recent.map((song) => song.id).toList(), ['song_3', 'song_2']);

    expect(await repository.getRecentlyAdded(-1), isEmpty);
  });
}

Future<_LibraryGraph> _createLibraryGraph(AppDatabase appDatabase) async {
  final db = await appDatabase.database;
  final now = DateTime.utc(2026, 9, 10);

  final artist = Artist(
    id: 'artist_graph',
    name: 'Graph Artist',
    canonicalName: 'graph artist',
    createdAt: now,
    updatedAt: now,
  );

  final album = Album(
    id: 'album_graph',
    artistId: artist.id,
    title: 'Graph Album',
    canonicalTitle: 'graph album',
    createdAt: now,
    updatedAt: now,
  );

  final edition = AlbumEdition(
    id: 'edition_graph',
    albumId: album.id,
    title: 'Graph Album',
    type: AlbumEditionType.standard,
    isPrimary: true,
    createdAt: now,
    updatedAt: now,
  );

  await ArtistDao(db).insert(artist);
  await AlbumDao(db).insert(album);
  await AlbumEditionDao(db).insert(edition);

  return _LibraryGraph(db: db, artist: artist, album: album, edition: edition);
}

Song _song({
  required String id,
  required String title,
  required _LibraryGraph graph,
  required DateTime createdAt,
}) {
  return Song(
    id: id,
    artistId: graph.artist.id,
    albumId: graph.album.id,
    albumEditionId: graph.edition.id,
    title: title,
    canonicalTitle: title.toLowerCase(),
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

class _LibraryGraph {
  const _LibraryGraph({
    required this.db,
    required this.artist,
    required this.album,
    required this.edition,
  });

  final Database db;
  final Artist artist;
  final Album album;
  final AlbumEdition edition;
}
