import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class SyncSchema {
  static const String cloudRevisionBaselinesTable =
      'sync_cloud_revision_baselines';
  static Future<void> create(DatabaseExecutor db) async {
    await createSyncState(db);
    await createSyncOutbox(db);
    await createCloudRevisionBaselines(db);
    await createArtistWriteJournal(db);
    await createArtistDependencyJournal(db);
    await createInboundDeferredRecords(db);
  }

  /// Verified cloud revisions the inbound cursor has passed without
  /// applying locally. Each row is a durable replay obligation.
  static const String inboundDeferredRecordsTable =
      'sync_inbound_deferred_records';

  static Future<void> createInboundDeferredRecords(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $inboundDeferredRecordsTable (
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
        server_updated_at TEXT NOT NULL
          CHECK (length(trim(server_updated_at)) > 0),
        reason TEXT NOT NULL
          CHECK (
            reason IN (
              'artworkDownloadRequired',
              'tombstoneRequiresLocalDeletion',
              'missingLocalArtwork'
            )
          ),
        deferred_at TEXT NOT NULL
          CHECK (length(trim(deferred_at)) > 0),

        PRIMARY KEY (user_id, entity_type, entity_id)
      )
    ''');
  }

  /// Durable snapshots of artist RPC requests awaiting verification.
  ///
  /// A newer outbox mutation cannot replace an unresolved request.
  static const String artistWriteJournalTable = 'sync_artist_write_journal';

  static Future<void> createArtistWriteJournal(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $artistWriteJournalTable (
        user_id TEXT NOT NULL
          CHECK (length(trim(user_id)) > 0),
        artist_id TEXT NOT NULL
          CHECK (length(trim(artist_id)) > 0),
        outbox_id TEXT NOT NULL
          CHECK (length(trim(outbox_id)) > 0),
        mutation_revision INTEGER NOT NULL
          CHECK (mutation_revision >= 1),
        operation TEXT NOT NULL
          CHECK (operation IN ('create', 'update', 'delete')),
        expected_server_revision INTEGER
          CHECK (
            (operation = 'create' AND expected_server_revision IS NULL)
            OR
            (operation IN ('update', 'delete')
              AND expected_server_revision IS NOT NULL
              AND expected_server_revision >= 1)
          ),
        request_json TEXT NOT NULL
          CHECK (length(trim(request_json)) > 0),
        created_at TEXT NOT NULL,

        PRIMARY KEY (user_id, outbox_id, mutation_revision),
        UNIQUE (user_id, artist_id)
      )
    ''');
  }

  /// Immutable dependency-only artist creation requests.
  ///
  /// These requests are not sync outbox mutations and must never
  /// acknowledge an explicit artist edit.
  static const String artistDependencyJournalTable =
      'sync_artist_dependency_journal';

  static Future<void> createArtistDependencyJournal(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $artistDependencyJournalTable (
        user_id TEXT NOT NULL
          CHECK (length(trim(user_id)) > 0),
        artist_id TEXT NOT NULL
          CHECK (length(trim(artist_id)) > 0),
        request_id TEXT NOT NULL
          CHECK (length(trim(request_id)) > 0),
        mutation_revision INTEGER NOT NULL DEFAULT 1
          CHECK (mutation_revision = 1),
        request_json TEXT NOT NULL
          CHECK (length(trim(request_json)) > 0),
        created_at TEXT NOT NULL
          CHECK (length(trim(created_at)) > 0),

        PRIMARY KEY (user_id, artist_id),
        UNIQUE (user_id, request_id)
      )
    ''');
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
