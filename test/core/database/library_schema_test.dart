import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';

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

  test('creates the current Sonus database tables', () async {
    final db = await appDatabase.database;

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
    ''');

    final names = tables.map((row) => row['name']).whereType<String>().toSet();

    expect(names, contains(DatabaseTables.artists));
    expect(names, contains(DatabaseTables.albums));
    expect(names, contains(DatabaseTables.albumEditions));
    expect(names, contains(DatabaseTables.songs));
    expect(names, contains(DatabaseTables.mediaFileBindings));
    expect(names, contains(DatabaseTables.importBatches));
    expect(names, contains(DatabaseTables.artworkAssets));
  });

  test('enables foreign key enforcement', () async {
    final db = await appDatabase.database;

    final result = await db.rawQuery('PRAGMA foreign_keys');

    expect(result.single['foreign_keys'], 1);
  });

  test('rejects album without an existing artist', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.albums, {
        'id': 'album_test',
        'artist_id': 'artist_missing',
        'title': 'Album',
        'canonical_title': 'album',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('allows separate artists with the same canonical name', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_same_name_1',
      'name': 'Same Name',
      'canonical_name': 'same name',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_same_name_2',
      'name': 'Same Name',
      'canonical_name': 'same name',
      'created_at': now,
      'updated_at': now,
    });

    final rows = await db.query(
      DatabaseTables.artists,
      where: 'canonical_name = ?',
      whereArgs: ['same name'],
    );

    expect(rows, hasLength(2));
    expect(rows.map((row) => row['id']).toSet(), {
      'artist_same_name_1',
      'artist_same_name_2',
    });
  });

  test(
    'artist blacklist defaults to false and accepts boolean values',
    () async {
      final db = await appDatabase.database;
      final now = DateTime.utc(2026, 9, 13).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_blacklist_default',
        'name': 'Default Artist',
        'canonical_name': 'default artist',
        'created_at': now,
        'updated_at': now,
      });

      final defaultRows = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_blacklist_default'],
      );

      expect(defaultRows.single['is_blacklisted'], 0);

      await db.update(
        DatabaseTables.artists,
        {'is_blacklisted': 1},
        where: 'id = ?',
        whereArgs: ['artist_blacklist_default'],
      );

      final blacklistedRows = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_blacklist_default'],
      );

      expect(blacklistedRows.single['is_blacklisted'], 1);
    },
  );

  test('rejects invalid artist blacklist values', () async {
    final db = await appDatabase.database;
    final now = DateTime.utc(2026, 9, 13).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.artists, {
        'id': 'artist_invalid_blacklist',
        'name': 'Invalid Artist',
        'canonical_name': 'invalid artist',
        'is_blacklisted': 2,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('song block defaults to false and accepts boolean values', () async {
    final db = await appDatabase.database;
    final now = DateTime.utc(2026, 9, 26).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_song_block',
      'name': 'Blocked Song Artist',
      'canonical_name': 'blocked song artist',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_song_block',
      'artist_id': 'artist_song_block',
      'title': 'Blocked Song Album',
      'canonical_title': 'blocked song album',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_song_block',
      'album_id': 'album_song_block',
      'title': 'Blocked Song Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.songs, {
      'id': 'song_block_default',
      'artist_id': 'artist_song_block',
      'album_id': 'album_song_block',
      'album_edition_id': 'edition_song_block',
      'title': 'Song',
      'canonical_title': 'song',
      'track_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'created_at': now,
      'updated_at': now,
    });

    var rows = await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_block_default'],
    );

    expect(rows.single['is_blocked'], 0);

    await db.update(
      DatabaseTables.songs,
      {'is_blocked': 1},
      where: 'id = ?',
      whereArgs: ['song_block_default'],
    );

    rows = await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_block_default'],
    );

    expect(rows.single['is_blocked'], 1);
  });

  test('rejects invalid song block values', () async {
    final db = await appDatabase.database;
    final now = DateTime.utc(2026, 9, 26).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_invalid_song_block',
      'name': 'Artist',
      'canonical_name': 'artist',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_invalid_song_block',
      'artist_id': 'artist_invalid_song_block',
      'title': 'Album',
      'canonical_title': 'album',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_invalid_song_block',
      'album_id': 'album_invalid_song_block',
      'title': 'Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    expect(
      () => db.insert(DatabaseTables.songs, {
        'id': 'song_invalid_block',
        'artist_id': 'artist_invalid_song_block',
        'album_id': 'album_invalid_song_block',
        'album_edition_id': 'edition_invalid_song_block',
        'title': 'Song',
        'canonical_title': 'song',
        'track_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 2,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
  test('media file location belongs to binding, not song', () async {
    final db = await appDatabase.database;

    final songColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.songs})',
    );

    final bindingColumns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.mediaFileBindings})',
    );

    final songColumnNames = songColumns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    final bindingColumnNames = bindingColumns
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();

    expect(songColumnNames, isNot(contains('file_path')));
    expect(songColumnNames, isNot(contains('normalized_path')));

    expect(bindingColumnNames, contains('file_path'));
    expect(bindingColumnNames, contains('normalized_path'));
  });

  test('core ownership foreign keys remain restrictive', () async {
    final db = await appDatabase.database;

    final albumKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(${DatabaseTables.albums})',
    );

    final songKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(${DatabaseTables.songs})',
    );

    expect(
      albumKeys.any(
        (row) =>
            row['table'] == DatabaseTables.artists &&
            row['on_delete'] == 'RESTRICT',
      ),
      isTrue,
    );

    expect(
      songKeys.any(
        (row) =>
            row['table'] == DatabaseTables.artists &&
            row['on_delete'] == 'RESTRICT',
      ),
      isTrue,
    );

    expect(
      songKeys.any(
        (row) =>
            row['table'] == DatabaseTables.albums &&
            row['on_delete'] == 'RESTRICT',
      ),
      isTrue,
    );

    expect(
      songKeys.any(
        (row) =>
            row['table'] == DatabaseTables.albumEditions &&
            row['on_delete'] == 'RESTRICT',
      ),
      isTrue,
    );

    expect(
      songKeys.any(
        (row) =>
            row['table'] == DatabaseTables.artworkAssets &&
            row['on_delete'] == 'SET NULL',
      ),
      isTrue,
    );
  });
}
