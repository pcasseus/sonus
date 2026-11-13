import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_tables.dart';
import '../../analytics/application/models/analytics_time_window.dart';
import '../application/wrapped_history_reader.dart';

/// [WrappedHistoryReader] over the app database. Read only; bounded by the
/// window, with the same two-second margin and exact filtering as Sonus
/// Pulse, so a period's genre plays are exactly its streams.
class SqliteWrappedHistoryReader implements WrappedHistoryReader {
  const SqliteWrappedHistoryReader(this._db);

  final DatabaseExecutor _db;

  static const _margin = Duration(seconds: 2);

  @override
  Future<List<WrappedGenrePlay>> genrePlays(AnalyticsTimeWindow window) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (window.startUtc case final start?) {
      clauses.add('q.qualified_at >= ?');
      args.add(start.toUtc().subtract(_margin).toIso8601String());
    }
    if (window.endUtc case final end?) {
      clauses.add('q.qualified_at < ?');
      args.add(end.toUtc().add(_margin).toIso8601String());
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await _db.rawQuery('''
      SELECT q.qualified_at AS at,
             COALESCE(
               NULLIF(TRIM(played.genre), ''),
               (SELECT NULLIF(TRIM(e.genre), '')
                FROM ${DatabaseTables.albumEditions} e
                WHERE e.album_id = q.album_id AND e.is_primary = 1
                ORDER BY e.id LIMIT 1)
             ) AS genre
      FROM ${DatabaseTables.qualifiedPlays} q
      LEFT JOIN ${DatabaseTables.albumEditions} played
        ON played.id = q.album_edition_id
      $where
    ''', args);
    return [
      for (final row in rows)
        if (DateTime.parse(row['at']! as String).toUtc() case final at
            when window.contains(at))
          WrappedGenrePlay(at: at, genre: row['genre'] as String?),
    ];
  }

  @override
  Future<int> streamsBefore(DateTime utc) async {
    // Counted in SQL well before the limit; the few rows within the margin
    // are compared exactly, as stored times may differ in precision.
    final limit = utc.toUtc();
    final early = limit.subtract(_margin).toIso8601String();
    final counted = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.qualifiedPlays} '
      'WHERE qualified_at < ?',
      [early],
    );
    final near = await _db.rawQuery(
      'SELECT qualified_at AS at FROM ${DatabaseTables.qualifiedPlays} '
      'WHERE qualified_at >= ? AND qualified_at < ?',
      [early, limit.add(_margin).toIso8601String()],
    );
    return (counted.single['n']! as int) +
        near
            .where(
              (row) => DateTime.parse(row['at']! as String).isBefore(limit),
            )
            .length;
  }

  @override
  Future<DateTime?> nthStreamAt(int n) async {
    if (n < 1) return null;
    final rows = await _db.rawQuery(
      'SELECT qualified_at AS at FROM ${DatabaseTables.qualifiedPlays} '
      'ORDER BY qualified_at, id LIMIT 1 OFFSET ?',
      [n - 1],
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['at']! as String).toUtc();
  }

  @override
  Future<List<WrappedChartLeader>> weeklyNumberOnes() async {
    final rows = await _db.rawQuery('''
      SELECT s.week_start_utc, s.week_end_utc,
             e.entity_id, e.title, e.artist_name
      FROM ${DatabaseTables.chartSnapshots} s
      JOIN ${DatabaseTables.chartEntries} e ON e.chart_snapshot_id = s.id
      WHERE s.chart_type = 'songs'
        AND s.finalized_at IS NOT NULL
        AND e.rank = 1
      ORDER BY s.week_start_utc
    ''');
    return [
      for (final row in rows)
        WrappedChartLeader(
          weekStartUtc: DateTime.parse(row['week_start_utc']! as String),
          weekEndUtc: DateTime.parse(row['week_end_utc']! as String),
          songId: row['entity_id']! as String,
          title: row['title']! as String,
          artistName: row['artist_name']! as String,
        ),
    ];
  }
}
