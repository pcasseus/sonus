import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/import_schema.dart';
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
      expect(AppDatabase.databaseVersion, 11);
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

  test('migration runner upgrades version 3 schema to version 4', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await DatabaseMigrations.migrate(db, oldVersion: 3, newVersion: 4);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final names = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(names, contains(DatabaseTables.syncState));
      expect(names, contains(DatabaseTables.syncOutbox));
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 4 schema to version 5', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 13).toIso8601String();

      await db.execute('''
        CREATE TABLE ${DatabaseTables.artists} (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          canonical_name TEXT NOT NULL,
          header_artwork_id TEXT,
          top_artists_artwork_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_before_blacklist',
        'name': 'Existing Artist',
        'canonical_name': 'existing artist',
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 4, newVersion: 5);

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.artists})',
      );

      expect(columns.map((row) => row['name']), contains('is_blacklisted'));

      final artists = await db.query(
        DatabaseTables.artists,
        where: 'id = ?',
        whereArgs: ['artist_before_blacklist'],
      );

      expect(artists, hasLength(1));
      expect(artists.single['is_blacklisted'], 0);
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 5 schema to version 7', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 17, 12).toIso8601String();

      await db.execute('PRAGMA foreign_keys = ON');

      await db.execute('''
        CREATE TABLE ${DatabaseTables.mediaFileBindings} (
          id TEXT PRIMARY KEY NOT NULL,
          song_id TEXT NOT NULL,
          file_path TEXT NOT NULL,
          normalized_path TEXT NOT NULL,
          is_available INTEGER NOT NULL DEFAULT 1,
          last_seen_at TEXT,
          file_size_bytes INTEGER,
          modified_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,

          UNIQUE(normalized_path)
        )
      ''');

      await db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'media_before_sources',
        'song_id': 'song_existing',
        'file_path': r'C:\Music\Artist\Album\Song.mp3',
        'normalized_path': 'c:/music/artist/album/song.mp3',
        'is_available': 1,
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 5, newVersion: 7);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final tableNames = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(tableNames, contains(DatabaseTables.importSources));

      final bindingColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.mediaFileBindings})',
      );

      expect(bindingColumns.map((row) => row['name']), contains('source_id'));

      final indexes = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND tbl_name = '${DatabaseTables.mediaFileBindings}'
      ''');

      expect(
        indexes.map((row) => row['name']),
        contains('idx_media_file_bindings_source_id'),
      );

      final existingRows = await db.query(
        DatabaseTables.mediaFileBindings,
        where: 'id = ?',
        whereArgs: ['media_before_sources'],
      );

      expect(existingRows, hasLength(1));
      expect(existingRows.single['song_id'], 'song_existing');
      expect(existingRows.single['source_id'], isNull);
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 6 schema to version 7', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 17, 12).toIso8601String();

      await db.execute('PRAGMA foreign_keys = ON');

      await ImportSchema.createImportSources(db);

      await db.execute('''
        CREATE TABLE ${DatabaseTables.mediaFileBindings} (
          id TEXT PRIMARY KEY NOT NULL,
          song_id TEXT NOT NULL,
          file_path TEXT NOT NULL,
          normalized_path TEXT NOT NULL,
          is_available INTEGER NOT NULL DEFAULT 1,
          last_seen_at TEXT,
          file_size_bytes INTEGER,
          modified_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,

          UNIQUE(normalized_path)
        )
      ''');

      await db.insert(DatabaseTables.importSources, {
        'id': 'import_source_existing',
        'root_path': r'C:\Music',
        'normalized_root_path': 'c:/music',
        'last_scanned_at': null,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.mediaFileBindings, {
        'id': 'media_before_source_column',
        'song_id': 'song_existing',
        'file_path': r'C:\Music\Artist\Album\Song.mp3',
        'normalized_path': 'c:/music/artist/album/song.mp3',
        'is_available': 1,
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 6, newVersion: 7);

      final bindingColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.mediaFileBindings})',
      );

      expect(bindingColumns.map((row) => row['name']), contains('source_id'));

      await db.update(
        DatabaseTables.mediaFileBindings,
        {'source_id': 'import_source_existing'},
        where: 'id = ?',
        whereArgs: ['media_before_source_column'],
      );

      final restored = await db.query(
        DatabaseTables.mediaFileBindings,
        where: 'id = ?',
        whereArgs: ['media_before_source_column'],
      );

      expect(restored, hasLength(1));
      expect(restored.single['source_id'], 'import_source_existing');

      final indexes = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND tbl_name = '${DatabaseTables.mediaFileBindings}'
      ''');

      expect(
        indexes.map((row) => row['name']),
        contains('idx_media_file_bindings_source_id'),
      );
    } finally {
      await db.close();
    }
  });
  test('migration runner upgrades version 7 schema to version 8', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('PRAGMA foreign_keys = ON');

      await db.execute('''
        CREATE TABLE ${DatabaseTables.songs} (
          id TEXT PRIMARY KEY NOT NULL
        )
      ''');

      await DatabaseMigrations.migrate(db, oldVersion: 7, newVersion: 8);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      expect(
        tables.map((row) => row['name']),
        contains(DatabaseTables.songImportReviews),
      );

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.songImportReviews})',
      );

      expect(
        columns.map((row) => row['name']),
        containsAll({
          'song_id',
          'metadata_source',
          'review_reasons',
          'resolved_at',
          'created_at',
          'updated_at',
        }),
      );

      final indexes = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND tbl_name = '${DatabaseTables.songImportReviews}'
      ''');

      expect(
        indexes.map((row) => row['name']),
        contains('idx_song_import_reviews_resolved_at'),
      );
    } finally {
      await db.close();
    }
  });
  test('migration runner upgrades version 8 schema to version 9', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 17).toIso8601String();

      await db.execute('''
        CREATE TABLE ${DatabaseTables.songs} (
          id TEXT PRIMARY KEY NOT NULL,
          track_number INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.insert(DatabaseTables.songs, {
        'id': 'song_before_disc_number',
        'track_number': 7,
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 8, newVersion: 9);

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.songs})',
      );

      expect(columns.map((row) => row['name']), contains('disc_number'));

      final rows = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_disc_number'],
      );

      expect(rows, hasLength(1));
      expect(rows.single['track_number'], 7);
      expect(rows.single['disc_number'], 1);
    } finally {
      await db.close();
    }
  });
  test(
    'migration runner upgrades version 9 schema to version 10 and preserves import reviews',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await db.execute('PRAGMA foreign_keys = ON');

        await db.execute('''
          CREATE TABLE ${DatabaseTables.songs} (
            id TEXT PRIMARY KEY NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DatabaseTables.songImportReviews} (
            song_id TEXT PRIMARY KEY NOT NULL,
            metadata_source TEXT NOT NULL
              CHECK (metadata_source IN ('embedded', 'fallback')),
            review_reasons TEXT NOT NULL DEFAULT '[]',
            resolved_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,

            FOREIGN KEY (song_id)
              REFERENCES ${DatabaseTables.songs}(id)
              ON UPDATE CASCADE
              ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_song_import_reviews_resolved_at
          ON ${DatabaseTables.songImportReviews}(resolved_at)
        ''');

        const embeddedSongId = 'song_embedded';
        const fallbackSongId = 'song_fallback';
        const mixedSongId = 'song_mixed';

        const createdAt = '2026-09-18T10:00:00.000Z';
        const updatedAt = '2026-09-19T11:00:00.000Z';
        const resolvedAt = '2026-09-19T12:00:00.000Z';

        await db.insert(DatabaseTables.songs, {'id': embeddedSongId});
        await db.insert(DatabaseTables.songs, {'id': fallbackSongId});
        await db.insert(DatabaseTables.songs, {'id': mixedSongId});

        await db.insert(DatabaseTables.songImportReviews, {
          'song_id': embeddedSongId,
          'metadata_source': 'embedded',
          'review_reasons': '["missingTrackNumber"]',
          'resolved_at': null,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await db.insert(DatabaseTables.songImportReviews, {
          'song_id': fallbackSongId,
          'metadata_source': 'fallback',
          'review_reasons': '["fallbackMetadata","missingDuration"]',
          'resolved_at': resolvedAt,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await DatabaseMigrations.migrate(db, oldVersion: 9, newVersion: 10);

        final preservedRows = await db.query(
          DatabaseTables.songImportReviews,
          orderBy: 'song_id ASC',
        );

        expect(preservedRows, hasLength(2));

        final embeddedRow = preservedRows.firstWhere(
          (row) => row['song_id'] == embeddedSongId,
        );

        expect(embeddedRow['metadata_source'], 'embedded');
        expect(embeddedRow['review_reasons'], '["missingTrackNumber"]');
        expect(embeddedRow['resolved_at'], isNull);
        expect(embeddedRow['created_at'], createdAt);
        expect(embeddedRow['updated_at'], updatedAt);

        final fallbackRow = preservedRows.firstWhere(
          (row) => row['song_id'] == fallbackSongId,
        );

        expect(fallbackRow['metadata_source'], 'fallback');
        expect(
          fallbackRow['review_reasons'],
          '["fallbackMetadata","missingDuration"]',
        );
        expect(fallbackRow['resolved_at'], resolvedAt);
        expect(fallbackRow['created_at'], createdAt);
        expect(fallbackRow['updated_at'], updatedAt);

        await db.insert(DatabaseTables.songImportReviews, {
          'song_id': mixedSongId,
          'metadata_source': 'mixed',
          'review_reasons': '["missingTrackNumber"]',
          'resolved_at': null,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        final mixedRows = await db.query(
          DatabaseTables.songImportReviews,
          where: 'song_id = ?',
          whereArgs: [mixedSongId],
        );

        expect(mixedRows, hasLength(1));
        expect(mixedRows.single['metadata_source'], 'mixed');

        final indexes = await db.rawQuery('''
          SELECT name
          FROM sqlite_master
          WHERE type = 'index'
            AND tbl_name = '${DatabaseTables.songImportReviews}'
        ''');

        expect(
          indexes.map((row) => row['name']),
          contains('idx_song_import_reviews_resolved_at'),
        );
      } finally {
        await db.close();
      }
    },
  );

  test('migration runner upgrades version 10 schema to version 11', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('PRAGMA foreign_keys = ON');

      await db.execute('''
        CREATE TABLE ${DatabaseTables.songs} (
          id TEXT PRIMARY KEY NOT NULL
        )
      ''');

      await db.insert(DatabaseTables.songs, {'id': 'song_before_lyrics'});

      await DatabaseMigrations.migrate(db, oldVersion: 10, newVersion: 11);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      expect(
        tables.map((row) => row['name']),
        contains(DatabaseTables.trackLyrics),
      );

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.trackLyrics})',
      );

      expect(
        columns.map((row) => row['name']),
        containsAll({
          'song_id',
          'plain_text',
          'synced_text',
          'created_at',
          'updated_at',
        }),
      );

      await db.insert(DatabaseTables.trackLyrics, {
        'song_id': 'song_before_lyrics',
        'plain_text': 'Plain lyric',
        'synced_text': '[00:01.00]Synced lyric',
        'created_at': '2026-09-20T12:00:00.000Z',
        'updated_at': '2026-09-20T12:00:00.000Z',
      });

      final rows = await db.query(DatabaseTables.trackLyrics);

      expect(rows, hasLength(1));
      expect(rows.single['song_id'], 'song_before_lyrics');
    } finally {
      await db.close();
    }
  });

  test('migration runner fails loudly for unknown future migration', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 11, newVersion: 12),
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
