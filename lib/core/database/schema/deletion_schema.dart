import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// App Update 1.2 (version 42): permanent deletion and duplicate merging.
///
/// Both tables are new; no existing table or row changes.
abstract final class DeletionSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createLedger(db);
    await createJournal(db);
  }

  /// Every record this device deleted on purpose, so nothing brings it
  /// back: stale cloud records, an archive download, an older backup or a
  /// rescan of a deleted file.
  ///
  /// Device-local: never backed up or restored, so a restore cannot erase
  /// it. It holds ids and file paths only, never names or counts, so a
  /// deleted song leaves no statistics behind.
  static Future<void> createLedger(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.libraryDeletionLedger} (
        entity_type TEXT NOT NULL
          CHECK (
            entity_type IN (
              'artist',
              'album',
              'albumEdition',
              'song',
              'playbackSession',
              'qualifiedPlay',
              'moment',
              'mediaFile'
            )
          ),
        entity_id TEXT NOT NULL CHECK (length(entity_id) > 0),
        reason TEXT NOT NULL
          CHECK (reason IN ('userDeletion', 'duplicateMerge')),
        operation_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_id)
      )
    ''');
  }

  /// One row per committed deletion or merge, written in the same
  /// transaction. The newest `committed_at` is the Moments cutoff (nothing
  /// before it may create a story), and `rebuilt_weeks` lists the chart
  /// weeks recalculated from the remaining plays, which publish no new
  /// stories. Internal state: never backed up or restored.
  static Future<void> createJournal(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.libraryDeletionJournal} (
        id TEXT PRIMARY KEY NOT NULL,
        operation TEXT NOT NULL
          CHECK (operation IN ('userDeletion', 'duplicateMerge')),
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        rebuilt_weeks TEXT NOT NULL DEFAULT '[]',
        summary TEXT NOT NULL DEFAULT '{}',
        committed_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_deletion_journal_committed
      ON ${DatabaseTables.libraryDeletionJournal}(committed_at)
    ''');
  }
}
