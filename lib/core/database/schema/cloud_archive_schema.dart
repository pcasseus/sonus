import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// What this device last agreed with the cloud archive, per record. Internal
/// sync state: never backed up or restored.
abstract final class CloudArchiveSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.cloudArchiveState} (
        user_id TEXT NOT NULL CHECK (length(trim(user_id)) > 0),
        kind TEXT NOT NULL CHECK (length(trim(kind)) > 0),
        record_key TEXT NOT NULL CHECK (length(record_key) > 0),
        fingerprint TEXT NOT NULL,
        server_revision INTEGER NOT NULL CHECK (server_revision >= 1),
        pending_apply INTEGER NOT NULL DEFAULT 0
          CHECK (pending_apply IN (0, 1)),
        cloud_deleted INTEGER NOT NULL DEFAULT 0
          CHECK (cloud_deleted IN (0, 1)),
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, kind, record_key)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_cloud_archive_state_pending
      ON ${DatabaseTables.cloudArchiveState}(user_id, pending_apply)
    ''');
  }
}
