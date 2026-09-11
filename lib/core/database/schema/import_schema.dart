import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class ImportSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createImportBatches(db);
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
