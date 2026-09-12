import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  sqfliteFfiInit();

  test('database reports the current Sonus schema version', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await appDatabase.database;

      final result = await db.rawQuery('PRAGMA user_version');

      expect(result.single['user_version'], AppDatabase.databaseVersion);
      expect(AppDatabase.databaseVersion, 3);
    } finally {
      await appDatabase.close();
    }
  });

  test('migration runner ignores same-version requests', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 3, newVersion: 3),
        completes,
      );
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 1 schema to version 2', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await LibrarySchema.create(db);

      await DatabaseMigrations.migrate(db, oldVersion: 1, newVersion: 2);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final names = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(names, contains(DatabaseTables.artists));
      expect(names, contains(DatabaseTables.albums));
      expect(names, contains(DatabaseTables.albumEditions));
      expect(names, contains(DatabaseTables.songs));
      expect(names, contains(DatabaseTables.mediaFileBindings));
      expect(names, contains(DatabaseTables.importBatches));
    } finally {
      await db.close();
    }
  });

  test('version 1 data survives migration to version 2', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await LibrarySchema.create(db);

      final now = DateTime.utc(2026, 9, 10).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_before_migration',
        'name': 'Existing Artist',
        'canonical_name': 'existing artist',
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 1, newVersion: 2);

      final artistRows = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_before_migration'],
      );

      expect(artistRows, hasLength(1));
      expect(artistRows.single['name'], 'Existing Artist');

      final importBatchColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.importBatches})',
      );

      expect(importBatchColumns, isNotEmpty);
    } finally {
      await db.close();
    }
  });

  test('migration runner fails loudly for unknown future migration', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 3, newVersion: 4),
        throwsA(isA<UnsupportedError>()),
      );
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 2 schema to version 3', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 11).toIso8601String();

      await db.execute('PRAGMA foreign_keys = ON');

      await db.execute('''
      CREATE TABLE ${DatabaseTables.artists} (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        canonical_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

      await db.execute('''
      CREATE TABLE ${DatabaseTables.albums} (
        id TEXT PRIMARY KEY NOT NULL,
        artist_id TEXT NOT NULL,
        title TEXT NOT NULL,
        canonical_title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (artist_id)
          REFERENCES ${DatabaseTables.artists}(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

      await db.execute('''
      CREATE TABLE ${DatabaseTables.albumEditions} (
        id TEXT PRIMARY KEY NOT NULL,
        album_id TEXT NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        release_date TEXT,
        genre TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (album_id)
          REFERENCES ${DatabaseTables.albums}(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

      await db.execute('''
      CREATE TABLE ${DatabaseTables.songs} (
        id TEXT PRIMARY KEY NOT NULL,
        artist_id TEXT NOT NULL,
        album_id TEXT NOT NULL,
        album_edition_id TEXT NOT NULL,
        title TEXT NOT NULL,
        canonical_title TEXT NOT NULL,
        track_number INTEGER NOT NULL DEFAULT 0,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        is_single INTEGER NOT NULL DEFAULT 0,
        featured_artists TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_before_artwork',
        'name': 'Existing Artist',
        'canonical_name': 'existing artist',
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 2, newVersion: 3);

      final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
    ''');

      final names = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(names, contains(DatabaseTables.artworkAssets));

      final artistColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.artists})',
      );

      final editionColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.albumEditions})',
      );

      final songColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.songs})',
      );

      expect(
        artistColumns.map((row) => row['name']),
        contains('header_artwork_id'),
      );
      expect(
        artistColumns.map((row) => row['name']),
        contains('top_artists_artwork_id'),
      );
      expect(editionColumns.map((row) => row['name']), contains('artwork_id'));
      expect(songColumns.map((row) => row['name']), contains('artwork_id'));

      final existingArtist = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_before_artwork'],
      );

      expect(existingArtist, hasLength(1));
      expect(existingArtist.single['name'], 'Existing Artist');
    } finally {
      await db.close();
    }
  });
}
