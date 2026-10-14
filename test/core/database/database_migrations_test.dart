import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';
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
      expect(AppDatabase.databaseVersion, 28);
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

  test('migration runner upgrades version 11 schema to version 12', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('PRAGMA foreign_keys = ON');

      await LibrarySchema.create(db);

      final now = DateTime.utc(2026, 9, 25, 12).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_before_analytics',
        'name': 'Analytics Artist',
        'canonical_name': 'analytics artist',
        'is_blacklisted': 0,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.albums, {
        'id': 'album_before_analytics',
        'artist_id': 'artist_before_analytics',
        'title': 'Analytics Album',
        'canonical_title': 'analytics album',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.albumEditions, {
        'id': 'edition_before_analytics',
        'album_id': 'album_before_analytics',
        'title': 'Analytics Album',
        'type': 'standard',
        'is_primary': 1,
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.songs, {
        'id': 'song_before_analytics',
        'artist_id': 'artist_before_analytics',
        'album_id': 'album_before_analytics',
        'album_edition_id': 'edition_before_analytics',
        'title': 'Analytics Song',
        'canonical_title': 'analytics song',
        'track_number': 1,
        'disc_number': 1,
        'duration_seconds': 240,
        'is_single': 0,
        'featured_artists': '[]',
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 11, newVersion: 12);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final tableNames = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(tableNames, contains(DatabaseTables.playbackSessions));
      expect(tableNames, contains(DatabaseTables.playbackListeningSegments));
      expect(tableNames, contains(DatabaseTables.qualifiedPlays));

      final playbackSessionColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.playbackSessions})',
      );

      expect(
        playbackSessionColumns.map((row) => row['name']),
        containsAll({
          'song_title',
          'artist_name',
          'album_title',
          'album_edition_title',
        }),
      );
      final preservedSongs = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_analytics'],
      );

      expect(preservedSongs, hasLength(1));
      expect(preservedSongs.single['title'], 'Analytics Song');
    } finally {
      await db.close();
    }
  });
  test('migration runner upgrades version 12 schema to version 13', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      final now = DateTime.utc(2026, 9, 26, 12).toIso8601String();

      await db.execute('''
        CREATE TABLE ${DatabaseTables.songs} (
          id TEXT PRIMARY KEY NOT NULL,
          artist_id TEXT NOT NULL,
          album_id TEXT NOT NULL,
          album_edition_id TEXT NOT NULL,
          title TEXT NOT NULL,
          canonical_title TEXT NOT NULL,
          track_number INTEGER NOT NULL DEFAULT 0,
          disc_number INTEGER NOT NULL DEFAULT 1,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          is_single INTEGER NOT NULL DEFAULT 0,
          featured_artists TEXT NOT NULL DEFAULT '[]',
          artwork_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.insert(DatabaseTables.songs, {
        'id': 'song_before_blocking',
        'artist_id': 'artist_existing',
        'album_id': 'album_existing',
        'album_edition_id': 'edition_existing',
        'title': 'Existing Song',
        'canonical_title': 'existing song',
        'track_number': 4,
        'disc_number': 2,
        'duration_seconds': 215,
        'is_single': 0,
        'featured_artists': '["Featured Artist"]',
        'artwork_id': null,
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 12, newVersion: 13);

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.songs})',
      );

      expect(columns.map((row) => row['name']), contains('is_blocked'));

      final songs = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_blocking'],
      );

      expect(songs, hasLength(1));
      expect(songs.single['title'], 'Existing Song');
      expect(songs.single['track_number'], 4);
      expect(songs.single['disc_number'], 2);
      expect(songs.single['featured_artists'], '["Featured Artist"]');
      expect(songs.single['is_blocked'], 0);

      await db.update(
        DatabaseTables.songs,
        {'is_blocked': 1},
        where: 'id = ?',
        whereArgs: ['song_before_blocking'],
      );

      final blockedSongs = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_blocking'],
      );

      expect(blockedSongs.single['is_blocked'], 1);
    } finally {
      await db.close();
    }
  });
  test('migration runner upgrades version 13 schema to version 14', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('PRAGMA foreign_keys = ON');

      await AnalyticsSchema.createPlaybackSessions(db);
      await AnalyticsSchema.createPlaybackListeningSegments(db);
      await AnalyticsSchema.createQualifiedPlays(db);

      await DatabaseMigrations.migrate(db, oldVersion: 13, newVersion: 14);

      final indexes = await db.rawQuery(
        '''
          SELECT name
          FROM sqlite_master
          WHERE type = 'index'
            AND tbl_name = ?
        ''',
        [DatabaseTables.playbackListeningSegments],
      );

      expect(
        indexes.map((row) => row['name']),
        contains('idx_playback_listening_segments_one_open_per_session'),
      );
    } finally {
      await db.close();
    }
  });

  test(
    'migration runner upgrades version 14 schema to version 15 and clears legacy artist blacklist state',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await LibrarySchema.create(db);

        final now = DateTime.utc(2026, 9, 27, 12).toIso8601String();

        await db.insert(DatabaseTables.artists, {
          'id': 'artist_legacy_blacklist',
          'name': 'Legacy Artist',
          'canonical_name': 'legacy artist',
          'is_blacklisted': 1,
          'created_at': now,
          'updated_at': now,
        });

        await DatabaseMigrations.migrate(db, oldVersion: 14, newVersion: 15);

        final rows = await db.query(
          DatabaseTables.artists,
          where: 'id = ?',
          whereArgs: ['artist_legacy_blacklist'],
        );

        expect(rows, hasLength(1));
        expect(rows.single['is_blacklisted'], 0);
        expect(rows.single['name'], 'Legacy Artist');
      } finally {
        await db.close();
      }
    },
  );

  test('migration runner upgrades version 15 schema to version 16', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await DatabaseMigrations.migrate(db, oldVersion: 15, newVersion: 16);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final names = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(names, contains(DatabaseTables.chartSnapshots));
      expect(names, contains(DatabaseTables.chartEntries));

      final snapshotColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.chartSnapshots})',
      );

      expect(
        snapshotColumns.map((row) => row['name']),
        containsAll({
          'id',
          'chart_type',
          'week_start_utc',
          'week_end_utc',
          'finalized_at',
          'revision',
          'created_at',
          'updated_at',
        }),
      );

      final entryColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.chartEntries})',
      );

      expect(
        entryColumns.map((row) => row['name']),
        containsAll({
          'id',
          'chart_snapshot_id',
          'entity_id',
          'title',
          'artist_name',
          'album_title',
          'rank',
          'qualified_stream_count',
          'previous_final_rank',
          'peak_rank',
          'peak_achieved_at',
          'weeks_on_chart',
          'movement',
          'last_qualified_at',
          'created_at',
          'updated_at',
        }),
      );
    } finally {
      await db.close();
    }
  });

  test('migration runner upgrades version 16 schema to version 17', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await ChartSchema.createChartSnapshots(db);
      await ChartSchema.createChartEntries(db);
      await ChartSchema.createChartIndexes(db);

      await DatabaseMigrations.migrate(db, oldVersion: 16, newVersion: 17);

      final tables = await db.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = ?
      ''',
        [DatabaseTables.chartMomentEvents],
      );

      expect(tables, hasLength(1));

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.chartMomentEvents})',
      );

      expect(
        columns.map((row) => row['name']),
        containsAll({
          'id',
          'deduplication_key',
          'user_id',
          'source_id',
          'chart_type',
          'scope',
          'event_type',
          'entity_id',
          'entity_title',
          'entity_artist_name',
          'entity_album_title',
          'related_entity_id',
          'related_entity_title',
          'related_entity_artist_name',
          'related_entity_album_title',
          'week_start_utc',
          'week_end_utc',
          'occurred_at',
          'created_at',
          'previous_rank',
          'current_rank',
          'threshold',
          'previous_peak_rank',
          'current_peak_rank',
          'qualified_stream_count',
          'milestone_value',
        }),
      );

      final indexes = await db.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND tbl_name = ?
      ''',
        [DatabaseTables.chartMomentEvents],
      );

      expect(
        indexes.map((row) => row['name']),
        containsAll({
          'idx_chart_moment_events_occurred',
          'idx_chart_moment_events_type_week',
          'idx_chart_moment_events_entity',
          'idx_chart_moment_events_user',
        }),
      );
    } finally {
      await db.close();
    }
  });
  test(
    'migration runner upgrades version 17 schema to version 18 and backfills chart artist ids',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await db.execute('''
          CREATE TABLE ${DatabaseTables.chartSnapshots} (
            id TEXT PRIMARY KEY NOT NULL,
            chart_type TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DatabaseTables.chartEntries} (
            id TEXT PRIMARY KEY NOT NULL,
            chart_snapshot_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            title TEXT NOT NULL,
            artist_name TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DatabaseTables.chartMomentEvents} (
            id TEXT PRIMARY KEY NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DatabaseTables.playbackSessions} (
            id TEXT PRIMARY KEY NOT NULL,
            song_id TEXT NOT NULL,
            artist_id TEXT NOT NULL,
            album_id TEXT NOT NULL,
            started_at TEXT NOT NULL
          )
        ''');

        await db.insert(DatabaseTables.chartSnapshots, {
          'id': 'songs-week',
          'chart_type': 'songs',
        });

        await db.insert(DatabaseTables.chartSnapshots, {
          'id': 'albums-week',
          'chart_type': 'albums',
        });

        await db.insert(DatabaseTables.chartEntries, {
          'id': 'song-entry',
          'chart_snapshot_id': 'songs-week',
          'entity_id': 'song-a',
          'title': 'Song A',
          'artist_name': 'Artist A',
        });

        await db.insert(DatabaseTables.chartEntries, {
          'id': 'album-entry',
          'chart_snapshot_id': 'albums-week',
          'entity_id': 'album-a',
          'title': 'Album A',
          'artist_name': 'Artist A',
        });

        await db.insert(DatabaseTables.playbackSessions, {
          'id': 'session-song',
          'song_id': 'song-a',
          'artist_id': 'artist-a',
          'album_id': 'album-a',
          'started_at': '2026-09-28T10:00:00.000Z',
        });

        await DatabaseMigrations.migrate(db, oldVersion: 17, newVersion: 18);

        final chartEntryColumns = await db.rawQuery(
          'PRAGMA table_info(${DatabaseTables.chartEntries})',
        );

        expect(
          chartEntryColumns.map((row) => row['name']),
          contains('artist_id'),
        );

        final momentColumns = await db.rawQuery(
          'PRAGMA table_info(${DatabaseTables.chartMomentEvents})',
        );

        expect(
          momentColumns.map((row) => row['name']),
          containsAll({'entity_artist_id', 'related_entity_artist_id'}),
        );

        final songRows = await db.query(
          DatabaseTables.chartEntries,
          where: 'id = ?',
          whereArgs: ['song-entry'],
        );

        final albumRows = await db.query(
          DatabaseTables.chartEntries,
          where: 'id = ?',
          whereArgs: ['album-entry'],
        );

        expect(songRows.single['artist_id'], 'artist-a');
        expect(albumRows.single['artist_id'], 'artist-a');
      } finally {
        await db.close();
      }
    },
  );
  test('migration runner upgrades version 18 schema to version 19', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('PRAGMA foreign_keys = ON');
      await LibrarySchema.create(db);

      await DatabaseMigrations.migrate(db, oldVersion: 18, newVersion: 19);

      final tables = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
      ''');

      final names = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(names, contains(DatabaseTables.playlists));
      expect(names, contains(DatabaseTables.playlistItems));

      final playlistColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.playlists})',
      );

      expect(
        playlistColumns.map((row) => row['name']),
        containsAll({'id', 'name', 'created_at', 'updated_at'}),
      );

      final itemColumns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.playlistItems})',
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
    } finally {
      await db.close();
    }
  });

  test(
    'migration runner upgrades version 19 schema to version 20 and preserves sync outbox',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await db.execute('''
          CREATE TABLE ${DatabaseTables.syncOutbox} (
            id TEXT PRIMARY KEY NOT NULL,
            user_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL
              CHECK (operation IN ('upsert', 'delete')),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,

            UNIQUE(user_id, entity_type, entity_id)
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_sync_outbox_user_created
          ON ${DatabaseTables.syncOutbox}(
            user_id,
            created_at,
            id
          )
        ''');

        const timestamp = '2026-09-30T12:00:00.000Z';

        await db.insert(DatabaseTables.syncOutbox, {
          'id': 'owned_before_v20',
          'user_id': 'user_1',
          'entity_type': 'artist',
          'entity_id': 'artist_1',
          'operation': 'upsert',
          'created_at': timestamp,
          'updated_at': timestamp,
        });

        await DatabaseMigrations.migrate(db, oldVersion: 19, newVersion: 20);

        final columns = await db.rawQuery(
          'PRAGMA table_info(${DatabaseTables.syncOutbox})',
        );

        final userIdColumn = columns.singleWhere(
          (row) => row['name'] == 'user_id',
        );

        expect(userIdColumn['notnull'], 0);

        final preserved = await db.query(
          DatabaseTables.syncOutbox,
          where: 'id = ?',
          whereArgs: ['owned_before_v20'],
        );

        expect(preserved, hasLength(1));
        expect(preserved.single['user_id'], 'user_1');
        expect(preserved.single['operation'], 'upsert');

        await db.insert(DatabaseTables.syncOutbox, {
          'id': 'unowned_after_v20',
          'user_id': null,
          'entity_type': 'song',
          'entity_id': 'song_1',
          'operation': 'delete',
          'created_at': timestamp,
          'updated_at': timestamp,
        });

        final unowned = await db.query(
          DatabaseTables.syncOutbox,
          where: 'user_id IS NULL',
        );

        expect(unowned, hasLength(1));

        final indexes = await db.rawQuery('''
          SELECT name
          FROM sqlite_master
          WHERE type = 'index'
            AND tbl_name = '${DatabaseTables.syncOutbox}'
        ''');

        expect(
          indexes.map((row) => row['name']),
          containsAll({
            'idx_sync_outbox_owned_entity',
            'idx_sync_outbox_unowned_entity',
            'idx_sync_outbox_user_created',
          }),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'migration runner upgrades version 21 schema to version 22 and preserves import reviews',
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
              CHECK (metadata_source IN ('embedded', 'mixed', 'fallback')),
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

        const songId = 'song_before_review_payload';
        const createdAt = '2026-10-01T12:00:00.000Z';
        const updatedAt = '2026-10-01T13:00:00.000Z';

        await db.insert(DatabaseTables.songs, {'id': songId});

        await db.insert(DatabaseTables.songImportReviews, {
          'song_id': songId,
          'metadata_source': 'embedded',
          'review_reasons': '["missingTrackNumber"]',
          'resolved_at': null,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await DatabaseMigrations.migrate(db, oldVersion: 21, newVersion: 22);

        final columns = await db.rawQuery(
          'PRAGMA table_info(${DatabaseTables.songImportReviews})',
        );

        expect(columns.map((row) => row['name']), contains('review_payload'));

        final rows = await db.query(
          DatabaseTables.songImportReviews,
          where: 'song_id = ?',
          whereArgs: [songId],
        );

        expect(rows, hasLength(1));
        expect(rows.single['metadata_source'], 'embedded');
        expect(rows.single['review_reasons'], '["missingTrackNumber"]');
        expect(rows.single['review_payload'], isNull);
        expect(rows.single['resolved_at'], isNull);
        expect(rows.single['created_at'], createdAt);
        expect(rows.single['updated_at'], updatedAt);
      } finally {
        await db.close();
      }
    },
  );
  test('version 23 membership authority defaults to inferred', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('''
          CREATE TABLE ${DatabaseTables.albumEditionTracks} (
            album_edition_id TEXT NOT NULL,
            song_id TEXT NOT NULL,
            disc_number INTEGER NOT NULL DEFAULT 1,
            track_number INTEGER NOT NULL DEFAULT 0,
            sort_position INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (album_edition_id, song_id)
          )
        ''');

      final now = DateTime.utc(2026, 10, 2).toIso8601String();

      await db.insert(DatabaseTables.albumEditionTracks, {
        'album_edition_id': 'edition-1',
        'song_id': 'song-1',
        'disc_number': 2,
        'track_number': 7,
        'sort_position': 4,
        'created_at': now,
        'updated_at': now,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 23, newVersion: 24);

      final rows = await db.query(DatabaseTables.albumEditionTracks);

      expect(rows, hasLength(1));
      expect(rows.single['disc_number'], 2);
      expect(rows.single['track_number'], 7);
      expect(rows.single['sort_position'], 4);
      expect(rows.single['numbering_authority'], 'inferred');
      expect(rows.single['ordering_authority'], 'inferred');
    } finally {
      await db.close();
    }
  });
  test('migration 24 tolerates authority columns already present', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('''
          CREATE TABLE ${DatabaseTables.albumEditionTracks} (
            album_edition_id TEXT NOT NULL,
            song_id TEXT NOT NULL,
            disc_number INTEGER NOT NULL DEFAULT 1,
            track_number INTEGER NOT NULL DEFAULT 0,
            sort_position INTEGER NOT NULL,
            numbering_authority TEXT NOT NULL DEFAULT 'inferred'
              CHECK (numbering_authority IN ('inferred', 'manual')),
            ordering_authority TEXT NOT NULL DEFAULT 'inferred'
              CHECK (ordering_authority IN ('inferred', 'manual')),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (album_edition_id, song_id)
          )
        ''');

      await DatabaseMigrations.migrate(db, oldVersion: 23, newVersion: 24);

      final columns = await db.rawQuery(
        'PRAGMA table_info(${DatabaseTables.albumEditionTracks})',
      );

      final names = columns.map((row) => row['name']).toList();

      expect(
        names.where((name) => name == 'numbering_authority'),
        hasLength(1),
      );

      expect(names.where((name) => name == 'ordering_authority'), hasLength(1));
    } finally {
      await db.close();
    }
  });
  test('migration 25 adds song version metadata with safe defaults', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      const createdAt = '2026-10-03T12:00:00.000Z';

      await db.execute('''
        CREATE TABLE ${DatabaseTables.songs} (
          id TEXT PRIMARY KEY NOT NULL,
          artist_id TEXT NOT NULL,
          album_id TEXT NOT NULL,
          album_edition_id TEXT NOT NULL,
          title TEXT NOT NULL,
          canonical_title TEXT NOT NULL,
          track_number INTEGER NOT NULL DEFAULT 0,
          disc_number INTEGER NOT NULL DEFAULT 1,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          is_single INTEGER NOT NULL DEFAULT 0,
          is_blocked INTEGER NOT NULL DEFAULT 0,
          featured_artists TEXT NOT NULL DEFAULT '[]',
          artwork_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.insert(DatabaseTables.songs, {
        'id': 'song_before_v25',
        'artist_id': 'artist_1',
        'album_id': 'album_1',
        'album_edition_id': 'edition_1',
        'title': 'Existing Song',
        'canonical_title': 'existing song',
        'track_number': 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 0,
        'featured_artists': '[]',
        'created_at': createdAt,
        'updated_at': createdAt,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 24, newVersion: 25);

      final rows = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_v25'],
      );

      expect(rows, hasLength(1));

      final row = rows.single;

      expect(row['id'], 'song_before_v25');
      expect(row['version_label'], isNull);
      expect(row['version_characteristics'], '[]');
      expect(row['release_status'], 'released');
      expect(row['is_leak'], 0);

      await db.update(
        DatabaseTables.songs,
        {
          'version_label': 'Early Mix',
          'version_characteristics': '["demo","acoustic"]',
          'release_status': 'unreleased',
          'is_leak': 1,
        },
        where: 'id = ?',
        whereArgs: ['song_before_v25'],
      );

      final updated = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_before_v25'],
      );

      expect(updated.single['version_label'], 'Early Mix');
      expect(updated.single['version_characteristics'], '["demo","acoustic"]');
      expect(updated.single['release_status'], 'unreleased');
      expect(updated.single['is_leak'], 1);

      await expectLater(
        db.update(
          DatabaseTables.songs,
          {'release_status': 'bootleg'},
          where: 'id = ?',
          whereArgs: ['song_before_v25'],
        ),
        throwsA(isA<DatabaseException>()),
      );

      await expectLater(
        db.update(
          DatabaseTables.songs,
          {'is_leak': 2},
          where: 'id = ?',
          whereArgs: ['song_before_v25'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });
  test('migration runner fails loudly for unknown future migration', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 28, newVersion: 29),
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
