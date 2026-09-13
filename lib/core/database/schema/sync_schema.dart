import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class SyncSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createSyncState(db);
    await createSyncOutbox(db);
  }

  static Future<void> createSyncState(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.syncState} (
        user_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        last_server_updated_at TEXT,
        last_server_id TEXT,
        updated_at TEXT NOT NULL,

        PRIMARY KEY (user_id, entity_type),

        CHECK (
          (last_server_updated_at IS NULL AND last_server_id IS NULL)
          OR
          (last_server_updated_at IS NOT NULL AND last_server_id IS NOT NULL)
        )
      )
    ''');
  }

  static Future<void> createSyncOutbox(DatabaseExecutor db) async {
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
      ON ${DatabaseTables.syncOutbox}(user_id, created_at, id)
    ''');
  }
}
