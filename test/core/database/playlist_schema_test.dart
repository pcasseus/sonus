import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  const now = '2026-09-29T12:00:00.000Z';

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<void> createLibrarySong(
    Database db, {
    String songId = 'song_playlist',
  }) async {
    await db.insert(DatabaseTables.artists, {
      'id': 'artist_playlist',
      'name': 'Playlist Artist',
      'canonical_name': 'playlist artist',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_playlist',
      'artist_id': 'artist_playlist',
      'title': 'Playlist Album',
      'canonical_title': 'playlist album',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_playlist',
      'album_id': 'album_playlist',
      'title': 'Playlist Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': 'artist_playlist',
      'album_id': 'album_playlist',
      'album_edition_id': 'edition_playlist',
      'title': 'Playlist Song',
      'canonical_title': 'playlist song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> createPlaylist(
    Database db, {
    String playlistId = 'playlist_test',
    String name = 'Test Playlist',
  }) async {
    await db.insert(DatabaseTables.playlists, {
      'id': playlistId,
      'name': name,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('creates playlist tables with expected columns', () async {
    final db = await appDatabase.database;

    final playlistColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.playlists})',
    );

    final itemColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.playlistItems})',
    );

    expect(
      playlistColumns.map((row) => row['name']),
      containsAll({'id', 'name', 'created_at', 'updated_at'}),
    );

    expect(
      itemColumns.map((row) => row['name']),
      containsAll({
        'id',
        'playlist_id',
        'song_id',
        'position',
        'created_at',
        'updated_at',
      }),
    );
  });

  test('creates playlist query indexes', () async {
    final db = await appDatabase.database;

    final indexes = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND tbl_name = '${DatabaseTables.playlistItems}'
    ''');

    final names = indexes.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'idx_playlist_items_playlist_position',
        'idx_playlist_items_song_id',
      }),
    );
  });

  test('rejects empty or whitespace-only playlist names', () async {
    final db = await appDatabase.database;

    await expectLater(
      db.insert(DatabaseTables.playlists, {
        'id': 'playlist_empty',
        'name': '',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert(DatabaseTables.playlists, {
        'id': 'playlist_whitespace',
        'name': '   ',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('playlist item requires existing playlist and song', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);

    await expectLater(
      db.insert(DatabaseTables.playlistItems, {
        'id': 'playlist_item_missing_playlist',
        'playlist_id': 'playlist_missing',
        'song_id': 'song_playlist',
        'position': 0,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await createPlaylist(db);

    await expectLater(
      db.insert(DatabaseTables.playlistItems, {
        'id': 'playlist_item_missing_song',
        'playlist_id': 'playlist_test',
        'song_id': 'song_missing',
        'position': 0,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects negative playlist item position', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);
    await createPlaylist(db);

    await expectLater(
      db.insert(DatabaseTables.playlistItems, {
        'id': 'playlist_item_negative',
        'playlist_id': 'playlist_test',
        'song_id': 'song_playlist',
        'position': -1,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('prevents adding the same song to one playlist twice', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);
    await createPlaylist(db);

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'playlist_item_one',
      'playlist_id': 'playlist_test',
      'song_id': 'song_playlist',
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });

    await expectLater(
      db.insert(DatabaseTables.playlistItems, {
        'id': 'playlist_item_two',
        'playlist_id': 'playlist_test',
        'song_id': 'song_playlist',
        'position': 1,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('allows the same song in different playlists', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);

    await createPlaylist(db, playlistId: 'playlist_one', name: 'Playlist One');

    await createPlaylist(db, playlistId: 'playlist_two', name: 'Playlist Two');

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'playlist_item_one',
      'playlist_id': 'playlist_one',
      'song_id': 'song_playlist',
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'playlist_item_two',
      'playlist_id': 'playlist_two',
      'song_id': 'song_playlist',
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query(DatabaseTables.playlistItems);

    expect(rows, hasLength(2));
  });

  test('deleting playlist cascades playlist items', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);
    await createPlaylist(db);

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'playlist_item_cascade',
      'playlist_id': 'playlist_test',
      'song_id': 'song_playlist',
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });

    await db.delete(
      DatabaseTables.playlists,
      where: 'id = ?',
      whereArgs: ['playlist_test'],
    );

    final rows = await db.query(
      DatabaseTables.playlistItems,
      where: 'id = ?',
      whereArgs: ['playlist_item_cascade'],
    );

    expect(rows, isEmpty);
  });

  test('deleting song cascades playlist membership', () async {
    final db = await appDatabase.database;

    await createLibrarySong(db);
    await createPlaylist(db);

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'playlist_item_song_cascade',
      'playlist_id': 'playlist_test',
      'song_id': 'song_playlist',
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });

    await db.delete(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_playlist'],
    );

    final rows = await db.query(
      DatabaseTables.playlistItems,
      where: 'id = ?',
      whereArgs: ['playlist_item_song_cascade'],
    );

    expect(rows, isEmpty);
  });
}
