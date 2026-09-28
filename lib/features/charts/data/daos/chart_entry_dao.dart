import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class ChartEntryDao {
  const ChartEntryDao(this.db);

  final DatabaseExecutor db;

  Future<void> insertAll(Iterable<Map<String, Object?>> rows) async {
    final batch = db.batch();

    for (final row in rows) {
      batch.insert(DatabaseTables.chartEntries, row);
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> findForSnapshot(String snapshotId) {
    return db.query(
      DatabaseTables.chartEntries,
      where: 'chart_snapshot_id = ?',
      whereArgs: [snapshotId],
      orderBy: 'rank ASC, entity_id ASC',
    );
  }

  Future<void> deleteForSnapshot(String snapshotId) async {
    await db.delete(
      DatabaseTables.chartEntries,
      where: 'chart_snapshot_id = ?',
      whereArgs: [snapshotId],
    );
  }
}
