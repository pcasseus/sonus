import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class SyncSchema {
  static const String cloudRevisionBaselinesTable =
      'sync_cloud_revision_baselines';
  static Future<void> create(DatabaseExecutor db) async {
    await createSyncState(db);
    await createSyncOutbox(db);
    await createCloudRevisionBaselines(db);
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

  static Future<void> createCloudRevisionBaselines(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $cloudRevisionBaselinesTable (
        user_id TEXT NOT NULL
          CHECK (length(trim(user_id)) > 0),
        entity_type TEXT NOT NULL
          CHECK (
            entity_type IN (
              'artworkAsset',
              'artist',
              'album',
              'albumEdition',
              'song'
            )
          ),
        entity_id TEXT NOT NULL
          CHECK (length(trim(entity_id)) > 0),
        server_revision INTEGER NOT NULL
          CHECK (server_revision >= 1),

        PRIMARY KEY (user_id, entity_type, entity_id)
      )
    ''');
  }

  static Future<void> createSyncOutbox(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.syncOutbox} (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL
          CHECK (operation IN ('upsert', 'delete')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        mutation_revision INTEGER NOT NULL DEFAULT 1
          CHECK (mutation_revision >= 1)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_outbox_owned_entity
      ON ${DatabaseTables.syncOutbox}(
        user_id,
        entity_type,
        entity_id
      )
      WHERE user_id IS NOT NULL
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_outbox_unowned_entity
      ON ${DatabaseTables.syncOutbox}(
        entity_type,
        entity_id
      )
      WHERE user_id IS NULL
    ''');

    await db.execute('''
      CREATE INDEX idx_sync_outbox_user_created
      ON ${DatabaseTables.syncOutbox}(user_id, created_at, id)
    ''');
  }
}
