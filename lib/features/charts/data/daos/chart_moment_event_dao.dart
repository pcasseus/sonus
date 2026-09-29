import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class ChartMomentEventDao {
  const ChartMomentEventDao(this.db);

  final DatabaseExecutor db;

  Future<void> insertIgnoreDuplicate(Map<String, Object?> row) async {
    final columns = row.keys.toList(growable: false);

    if (columns.isEmpty) {
      throw ArgumentError.value(
        row,
        'row',
        'Chart Moment row must contain at least one column.',
      );
    }

    final columnSql = columns.map((column) => '"$column"').join(', ');
    final placeholderSql = List.filled(columns.length, '?').join(', ');

    await db.rawInsert(
      'INSERT INTO "${DatabaseTables.chartMomentEvents}" '
      '($columnSql) '
      'VALUES ($placeholderSql) '
      'ON CONFLICT(deduplication_key) DO NOTHING',
      [for (final column in columns) row[column]],
    );
  }

  Future<void> deleteFinalizedForWeek({
    required String chartType,
    required DateTime weekStartUtc,
  }) {
    return db.delete(
      DatabaseTables.chartMomentEvents,
      where: 'chart_type = ? AND scope = ? AND week_start_utc = ?',
      whereArgs: [
        chartType,
        'finalized',
        weekStartUtc.toUtc().toIso8601String(),
      ],
    );
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.chartMomentEvents,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.single;
  }

  Future<List<Map<String, Object?>>> findRecent({int? limit}) {
    return db.query(
      DatabaseTables.chartMomentEvents,
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
  }
}
