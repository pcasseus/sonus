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

  Future<bool> hasFinalizedForWeek({
    required String chartType,
    required DateTime weekStartUtc,
  }) async {
    final rows = await db.query(
      DatabaseTables.chartMomentEvents,
      columns: const ['id'],
      where: 'chart_type = ? AND scope = ? AND week_start_utc = ?',
      whereArgs: [
        chartType,
        'finalized',
        weekStartUtc.toUtc().toIso8601String(),
      ],
      limit: 1,
    );

    return rows.isNotEmpty;
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

  /// Up to [limit] rows after (older than) [beforeOccurredAt] and
  /// [beforeId] in the feed order. The occurred index serves the range and
  /// the order.
  Future<List<Map<String, Object?>>> findPage({
    String? beforeOccurredAt,
    String? beforeId,
    required int limit,
  }) {
    final hasCursor = beforeOccurredAt != null && beforeId != null;

    return db.query(
      DatabaseTables.chartMomentEvents,
      where: hasCursor
          ? 'occurred_at <= ? AND (occurred_at < ? OR id < ?)'
          : null,
      whereArgs: hasCursor
          ? [beforeOccurredAt, beforeOccurredAt, beforeId]
          : null,
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
  }
}
