import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class ChartSnapshotDao {
  const ChartSnapshotDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Map<String, Object?> row) async {
    await db.insert(DatabaseTables.chartSnapshots, row);
  }

  Future<void> update(Map<String, Object?> row) async {
    final id = row['id'];

    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Chart snapshot id must not be blank.',
      );
    }

    final updated = await db.update(
      DatabaseTables.chartSnapshots,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updated != 1) {
      throw StateError('Chart snapshot not found: $id');
    }
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.chartSnapshots,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, Object?>?> findForWeek({
    required String chartType,
    required DateTime weekStartUtc,
  }) async {
    final rows = await db.query(
      DatabaseTables.chartSnapshots,
      where: 'chart_type = ? AND week_start_utc = ?',
      whereArgs: [chartType, weekStartUtc.toUtc().toIso8601String()],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> findHistory(
    String chartType, {
    int? limit,
  }) {
    if (limit != null && limit <= 0) {
      return Future.value(const []);
    }

    return db.query(
      DatabaseTables.chartSnapshots,
      where: 'chart_type = ? AND finalized_at IS NOT NULL',
      whereArgs: [chartType],
      orderBy: 'week_start_utc DESC, id ASC',
      limit: limit,
    );
  }

  Future<void> deleteById(String id) async {
    await db.delete(
      DatabaseTables.chartSnapshots,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
