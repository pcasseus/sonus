import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class ChartSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createChartSnapshots(db);
    await createChartEntries(db);
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

  static Future<void> createIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX idx_chart_snapshots_week
      ON ${DatabaseTables.chartSnapshots}(week_start_utc)
    ''');

    await db.execute('''
      CREATE INDEX idx_chart_snapshots_type_week
      ON ${DatabaseTables.chartSnapshots}(chart_type, week_start_utc)
    ''');

    await db.execute('''
      CREATE INDEX idx_chart_entries_snapshot_rank
      ON ${DatabaseTables.chartEntries}(chart_snapshot_id, rank)
    ''');

    await db.execute('''
      CREATE INDEX idx_chart_entries_entity
      ON ${DatabaseTables.chartEntries}(entity_id)
    ''');
  }
}
