import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class ImportSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createImportSources(db);
    await createImportBatches(db);
  }

  static Future<void> createImportSources(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.importSources} (
        id TEXT PRIMARY KEY NOT NULL,
        root_path TEXT NOT NULL,
        normalized_root_path TEXT NOT NULL,
        last_scanned_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        UNIQUE(normalized_root_path)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_import_sources_last_scanned
      ON ${DatabaseTables.importSources}(last_scanned_at)
    ''');
  }

  static Future<void> createSongImportReviews(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.songImportReviews} (
        song_id TEXT PRIMARY KEY NOT NULL,
        metadata_source TEXT NOT NULL
          CHECK (metadata_source IN ('embedded', 'mixed', 'fallback')),
        review_reasons TEXT NOT NULL DEFAULT '[]',
        review_payload TEXT,
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
  }

  static Future<void> createImportBatches(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.importBatches} (
        id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL
          CHECK (status IN ('pending', 'running', 'completed')),
        total_count INTEGER NOT NULL DEFAULT 0
          CHECK (total_count >= 0),
        imported_count INTEGER NOT NULL DEFAULT 0
          CHECK (imported_count >= 0),
        relinked_count INTEGER NOT NULL DEFAULT 0
          CHECK (relinked_count >= 0),
        skipped_count INTEGER NOT NULL DEFAULT 0
          CHECK (skipped_count >= 0),
        failed_count INTEGER NOT NULL DEFAULT 0
          CHECK (failed_count >= 0),
        created_at TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_import_batches_created_at
      ON ${DatabaseTables.importBatches}(created_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_import_batches_status
      ON ${DatabaseTables.importBatches}(status)
    ''');
  }
}
