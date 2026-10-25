import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class ChartSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createChartSnapshots(db);
    await createChartEntries(db);
    await createChartMomentEvents(db);
    await createIndexes(db);
  }

  static Future<void> createChartSnapshots(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.chartSnapshots} (
        id TEXT PRIMARY KEY NOT NULL,

        chart_type TEXT NOT NULL
          CHECK (chart_type IN ('songs', 'albums')),

        week_start_utc TEXT NOT NULL,
        week_end_utc TEXT NOT NULL,

        finalized_at TEXT,

        revision INTEGER NOT NULL DEFAULT 1
          CHECK (revision >= 1),

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        UNIQUE(chart_type, week_start_utc),

        CHECK (week_end_utc > week_start_utc)
      )
    ''');
  }

  static Future<void> createChartEntries(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.chartEntries} (
        id TEXT PRIMARY KEY NOT NULL,

        chart_snapshot_id TEXT NOT NULL,

        entity_id TEXT NOT NULL,

        title TEXT NOT NULL,
        artist_id TEXT,
        artist_name TEXT NOT NULL,
        album_title TEXT,

        rank INTEGER NOT NULL
          CHECK (rank >= 1 AND rank <= 200),

        qualified_stream_count INTEGER NOT NULL
          CHECK (qualified_stream_count > 0),

        previous_final_rank INTEGER
          CHECK (
            previous_final_rank IS NULL OR
            (previous_final_rank >= 1 AND previous_final_rank <= 100)
          ),

        peak_rank INTEGER NOT NULL
          CHECK (peak_rank >= 1 AND peak_rank <= 200),

        peak_achieved_at TEXT NOT NULL,

        weeks_on_chart INTEGER NOT NULL DEFAULT 0
          CHECK (weeks_on_chart >= 0),

        movement TEXT NOT NULL
          CHECK (
            movement IN (
              'newEntry',
              'reentry',
              'up',
              'down',
              'same'
            )
          ),

        last_qualified_at TEXT NOT NULL,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (chart_snapshot_id)
          REFERENCES ${DatabaseTables.chartSnapshots}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,

        UNIQUE(chart_snapshot_id, entity_id),
        UNIQUE(chart_snapshot_id, rank)
      )
    ''');
  }

  static Future<void> createChartMomentEvents(
    DatabaseExecutor db, {
    String table = DatabaseTables.chartMomentEvents,
  }) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id TEXT PRIMARY KEY NOT NULL,

        deduplication_key TEXT NOT NULL UNIQUE,

        user_id TEXT,
        source_id TEXT,

        chart_type TEXT NOT NULL
          CHECK (chart_type IN ('songs', 'albums')),

        scope TEXT NOT NULL
          CHECK (scope IN ('live', 'finalized', 'allTime')),

        event_type TEXT NOT NULL
          CHECK (length(event_type) > 0),

        entity_id TEXT NOT NULL,
        entity_title TEXT NOT NULL,
        entity_artist_id TEXT,
        entity_artist_name TEXT NOT NULL,
        entity_album_title TEXT,

        related_entity_id TEXT,
        related_entity_title TEXT,
        related_entity_artist_id TEXT,
        related_entity_artist_name TEXT,
        related_entity_album_title TEXT,

        week_start_utc TEXT NOT NULL,
        week_end_utc TEXT NOT NULL,

        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,

        previous_rank INTEGER
          CHECK (
            previous_rank IS NULL OR
            (previous_rank >= 1 AND previous_rank <= 200)
          ),

        current_rank INTEGER
          CHECK (
            current_rank IS NULL OR
            (current_rank >= 1 AND current_rank <= 200)
          ),

        threshold INTEGER
          CHECK (
            threshold IS NULL OR
            (threshold >= 1 AND threshold <= 200)
          ),

        previous_peak_rank INTEGER
          CHECK (
            previous_peak_rank IS NULL OR
            (previous_peak_rank >= 1 AND previous_peak_rank <= 200)
          ),

        current_peak_rank INTEGER
          CHECK (
            current_peak_rank IS NULL OR
            (current_peak_rank >= 1 AND current_peak_rank <= 200)
          ),

        qualified_stream_count INTEGER
          CHECK (
            qualified_stream_count IS NULL OR
            qualified_stream_count >= 0
          ),

        milestone_value INTEGER
          CHECK (
            milestone_value IS NULL OR
            milestone_value >= 0
          ),

        CHECK (week_end_utc > week_start_utc),

        CHECK (
          (
            related_entity_id IS NULL AND
            related_entity_title IS NULL AND
            related_entity_artist_name IS NULL AND
            related_entity_album_title IS NULL
          )
          OR
          (
            related_entity_id IS NOT NULL AND
            related_entity_title IS NOT NULL AND
            related_entity_artist_name IS NOT NULL
          )
        )
      )
    ''');
  }

  /// Migration 36: the scope check gains 'allTime'. Columns, rows and
  /// indexes are unchanged.
  static Future<void> rebuildChartMomentEvents(DatabaseExecutor db) async {
    const table = DatabaseTables.chartMomentEvents;
    const staging = '${table}_rebuild';

    final columns = [
      for (final row in await db.rawQuery('PRAGMA table_info($table)'))
        row['name']! as String,
    ].join(', ');

    if (columns.isEmpty) {
      await createChartMomentEvents(db);
      await createChartMomentIndexes(db);
      return;
    }

    await createChartMomentEvents(db, table: staging);
    await db.execute(
      'INSERT INTO $staging ($columns) SELECT $columns FROM $table',
    );
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE $staging RENAME TO $table');
    await createChartMomentIndexes(db);
  }

  static Future<void> createIndexes(DatabaseExecutor db) async {
    await createChartIndexes(db);
    await createChartMomentIndexes(db);
  }

  static Future<void> createChartIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_snapshots_week
      ON ${DatabaseTables.chartSnapshots}(week_start_utc)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_snapshots_type_week
      ON ${DatabaseTables.chartSnapshots}(chart_type, week_start_utc)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_entries_snapshot_rank
      ON ${DatabaseTables.chartEntries}(chart_snapshot_id, rank)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_entries_entity
      ON ${DatabaseTables.chartEntries}(entity_id)
    ''');
  }

  static Future<void> createChartMomentIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_moment_events_occurred
      ON ${DatabaseTables.chartMomentEvents}(occurred_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_moment_events_type_week
      ON ${DatabaseTables.chartMomentEvents}(
        chart_type,
        week_start_utc,
        occurred_at DESC
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_moment_events_entity
      ON ${DatabaseTables.chartMomentEvents}(entity_id, occurred_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chart_moment_events_user
      ON ${DatabaseTables.chartMomentEvents}(user_id, occurred_at DESC)
    ''');
  }
}
