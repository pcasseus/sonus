import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
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

  Future<void> createLibraryGraph(Database db) async {
    final now = DateTime.utc(2026, 9, 10, 12).toIso8601String();

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_hardening',
      'name': 'Artist',
      'canonical_name': 'artist hardening',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_hardening',
      'artist_id': 'artist_hardening',
      'title': 'Album',
      'canonical_title': 'album hardening',
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_hardening',
      'album_id': 'album_hardening',
      'title': 'Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert(DatabaseTables.songs, {
      'id': 'song_hardening',
      'artist_id': 'artist_hardening',
      'album_id': 'album_hardening',
      'album_edition_id': 'edition_hardening',
      'title': 'Song',
      'canonical_title': 'song hardening',
      'track_number': 1,
      'duration_seconds': 200,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': now,
      'updated_at': now,
    });
  }

  test('rejects negative song duration', () async {
    final db = await appDatabase.database;
    await createLibraryGraph(db);

    expect(
      () => db.update(
        DatabaseTables.songs,
        {'duration_seconds': -1},
        where: 'id = ?',
        whereArgs: ['song_hardening'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects invalid SQLite boolean values', () async {
    final db = await appDatabase.database;
    await createLibraryGraph(db);

    expect(
      () => db.update(
        DatabaseTables.songs,
        {'is_single': 2},
        where: 'id = ?',
        whereArgs: ['song_hardening'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects duplicate normalized media path', () async {
    final db = await appDatabase.database;
    await createLibraryGraph(db);

    final now = DateTime.utc(2026, 9, 10, 12).toIso8601String();

    await db.insert(DatabaseTables.mediaFileBindings, {
      'id': 'binding_one',
      'song_id': 'song_hardening',
      'file_path': r'C:\Music\Song.mp3',
      'normalized_path': 'c:/music/song.mp3',
      'is_available': 1,
      'created_at': now,
      'updated_at': now,
    });

    expect(
      () => db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'binding_two',
        'song_id': 'song_hardening',
        'file_path': r'C:\MUSIC\SONG.mp3',
        'normalized_path': 'c:/music/song.mp3',
        'is_available': 1,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('prevents deleting parent entities while children exist', () async {
    final db = await appDatabase.database;
    await createLibraryGraph(db);

    expect(
      () => db.delete(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_hardening'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      () => db.delete(
        DatabaseTables.albums,
        where: 'id = ?',
        whereArgs: ['album_hardening'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      () => db.delete(
        DatabaseTables.albumEditions,
        where: 'id = ?',
        whereArgs: ['edition_hardening'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('database survives close and reopen', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'sonus_next_database_test_',
    );

    final databasePath = path.join(tempDirectory.path, 'persistence.db');

    final firstDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    try {
      final db = await firstDatabase.database;

      final now = DateTime.utc(2026, 9, 10, 12).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_persistent',
        'name': 'Persistent Artist',
        'canonical_name': 'persistent artist',
        'created_at': now,
        'updated_at': now,
      });

      await firstDatabase.close();

      final reopenedDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      try {
        final reopened = await reopenedDatabase.database;

        final rows = await reopened.query(
          DatabaseTables.artists,
          where: 'id = ?',
          whereArgs: ['artist_persistent'],
        );

        expect(rows, hasLength(1));
        expect(rows.single['name'], 'Persistent Artist');
      } finally {
        await reopenedDatabase.close();
      }
    } finally {
      await firstDatabase.close();

      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });
}
