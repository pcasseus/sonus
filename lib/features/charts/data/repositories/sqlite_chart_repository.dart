import '../../../../core/database/app_database.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/repositories/chart_repository.dart';
import '../daos/chart_entry_dao.dart';
import '../daos/chart_snapshot_dao.dart';
import '../mappers/chart_entry_row_mapper.dart';
import '../mappers/chart_snapshot_row_mapper.dart';

class SqliteChartRepository implements ChartRepository {
  const SqliteChartRepository(this.database);

  final AppDatabase database;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) {
    return database.transaction((transaction) async {
      final snapshotDao = ChartSnapshotDao(transaction);
      final entryDao = ChartEntryDao(transaction);

      final existing = await snapshotDao.findForWeek(
        chartType: snapshot.chartType.name,
        weekStartUtc: snapshot.weekStartUtc,
      );

      if (existing != null) {
        final existingRevision = existing['revision']! as int;

        if (snapshot.revision < existingRevision) {
          throw StateError(
            'Cannot replace chart snapshot revision '
            '$existingRevision with older revision ${snapshot.revision}.',
          );
        }
      }

      final now = DateTime.now().toUtc();

      if (existing == null) {
        await snapshotDao.insert(
          ChartSnapshotRowMapper.toRow(
            snapshot: snapshot,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        final existingId = existing['id']! as String;

        if (existingId != snapshot.id) {
          await snapshotDao.deleteById(existingId);

          await snapshotDao.insert(
            ChartSnapshotRowMapper.toRow(
              snapshot: snapshot,
              createdAt: DateTime.parse(existing['created_at']! as String),
              updatedAt: now,
            ),
          );
        } else {
          await snapshotDao.update(
            ChartSnapshotRowMapper.toRow(
              snapshot: snapshot,
              createdAt: DateTime.parse(existing['created_at']! as String),
              updatedAt: now,
            ),
          );

          await entryDao.deleteForSnapshot(snapshot.id);
        }
      }

      await entryDao.insertAll(
        snapshot.entries.map(
          (entry) => ChartEntryRowMapper.toRow(
            snapshotId: snapshot.id,
            entry: entry,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    });
  }

  @override
  Future<ChartSnapshot?> getById(String id) async {
    final db = await database.database;

    final snapshotDao = ChartSnapshotDao(db);
    final entryDao = ChartEntryDao(db);

    final snapshotRow = await snapshotDao.findById(id);

    if (snapshotRow == null) {
      return null;
    }

    return _hydrate(snapshotRow: snapshotRow, entryDao: entryDao);
  }

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    final db = await database.database;

    final snapshotDao = ChartSnapshotDao(db);
    final entryDao = ChartEntryDao(db);

    final snapshotRow = await snapshotDao.findForWeek(
      chartType: chartType.name,
      weekStartUtc: weekStartUtc,
    );

    if (snapshotRow == null) {
      return null;
    }

    return _hydrate(snapshotRow: snapshotRow, entryDao: entryDao);
  }

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final db = await database.database;

    final snapshotDao = ChartSnapshotDao(db);
    final entryDao = ChartEntryDao(db);

    final snapshotRows = await snapshotDao.findHistory(
      chartType.name,
      limit: limit,
    );

    final snapshots = <ChartSnapshot>[];

    for (final snapshotRow in snapshotRows) {
      snapshots.add(
        await _hydrate(snapshotRow: snapshotRow, entryDao: entryDao),
      );
    }

    return List<ChartSnapshot>.unmodifiable(snapshots);
  }

  static Future<ChartSnapshot> _hydrate({
    required Map<String, Object?> snapshotRow,
    required ChartEntryDao entryDao,
  }) async {
    final snapshotId = snapshotRow['id']! as String;

    final entryRows = await entryDao.findForSnapshot(snapshotId);

    final entries = entryRows
        .map(ChartEntryRowMapper.fromRow)
        .toList(growable: false);

    return ChartSnapshotRowMapper.fromRow(
      snapshotRow: snapshotRow,
      entries: entries,
    );
  }
}
