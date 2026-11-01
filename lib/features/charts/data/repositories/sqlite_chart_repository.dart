import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/repositories/chart_entity_history_reader.dart';
import '../../domain/repositories/chart_repository.dart';
import '../../domain/repositories/chart_week_finalizer.dart';
import '../daos/chart_entry_dao.dart';
import '../daos/chart_moment_event_dao.dart';
import '../daos/chart_snapshot_dao.dart';
import '../mappers/chart_entry_row_mapper.dart';
import '../mappers/chart_moment_event_row_mapper.dart';
import '../mappers/chart_snapshot_row_mapper.dart';
import 'sqlite_chart_moment_repository.dart';

/// A finalized chart week is never rewritten (SN-50 F6).
class FinalizedChartWeekFrozen extends StateError {
  FinalizedChartWeekFrozen(ChartType chartType, DateTime weekStartUtc)
    : super(
        'The ${chartType.name} chart for the week starting '
        '${weekStartUtc.toUtc().toIso8601String()} is finalized and is '
        'never rewritten.',
      );
}

class SqliteChartRepository
    implements ChartRepository, ChartWeekFinalizer, ChartEntityHistoryReader {
  const SqliteChartRepository(this.database);

  final AppDatabase database;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) {
    return database.transaction(
      (transaction) => _writeSnapshot(transaction, snapshot),
    );
  }

  /// One transaction: the week is re-read inside it, a week already
  /// finalized is returned untouched, and otherwise its snapshot, entries
  /// and Moments are written together. Published Moments are never
  /// replaced or added to. Validation happens before the transaction, so
  /// the restore admission check runs with no await before it.
  @override
  Future<ChartWeekFinalization> finalizeWeek({
    required ChartSnapshot snapshot,
    List<ChartMomentEvent>? moments,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.id,
        'snapshot',
        'Only a finalized chart week can be finalized.',
      );
    }

    final publication = moments == null
        ? null
        : List<ChartMomentEvent>.unmodifiable(moments);
    if (publication != null) {
      validateFinalizedPublication(
        chartType: snapshot.chartType,
        weekStartUtc: snapshot.weekStartUtc,
        events: publication,
      );
    }

    return database.transaction((transaction) async {
      final existing = await ChartSnapshotDao(transaction).findForWeek(
        chartType: snapshot.chartType.name,
        weekStartUtc: snapshot.weekStartUtc,
      );

      if (existing != null && existing['finalized_at'] != null) {
        return ChartWeekFinalization(
          snapshot: await _hydrate(
            snapshotRow: existing,
            entryDao: ChartEntryDao(transaction),
          ),
          wasAlreadyFinalized: true,
          moments: ChartFinalizedMoments.notRequested,
        );
      }

      await _writeSnapshot(transaction, snapshot);

      if (publication == null) {
        return ChartWeekFinalization(
          snapshot: snapshot,
          wasAlreadyFinalized: false,
          moments: ChartFinalizedMoments.notRequested,
        );
      }

      final momentDao = ChartMomentEventDao(transaction);
      if (await momentDao.hasFinalizedForWeek(
        chartType: snapshot.chartType.name,
        weekStartUtc: snapshot.weekStartUtc.toUtc(),
      )) {
        // Left by the earlier write order (Moments, then the snapshot) when
        // a pass stopped between the two. The published Moments stay as
        // they are; the snapshot is stored now. Logged, never repaired.
        developer.log(
          'Finalized ${snapshot.chartType.name} week '
          '${snapshot.weekStartUtc.toUtc().toIso8601String()} already had '
          'published Moments but no snapshot; they are kept unchanged.',
          name: 'sonus.charts',
          level: 900,
        );
        return ChartWeekFinalization(
          snapshot: snapshot,
          wasAlreadyFinalized: false,
          moments: ChartFinalizedMoments.keptEarlier,
        );
      }

      for (final event in publication) {
        await momentDao.insertIgnoreDuplicate(
          ChartMomentEventRowMapper.toRow(event),
        );
      }

      return ChartWeekFinalization(
        snapshot: snapshot,
        wasAlreadyFinalized: false,
        moments: ChartFinalizedMoments.published,
      );
    });
  }

  static Future<void> _writeSnapshot(
    DatabaseExecutor transaction,
    ChartSnapshot snapshot,
  ) async {
    final snapshotDao = ChartSnapshotDao(transaction);
    final entryDao = ChartEntryDao(transaction);

    final existing = await snapshotDao.findForWeek(
      chartType: snapshot.chartType.name,
      weekStartUtc: snapshot.weekStartUtc,
    );

    if (existing != null) {
      if (existing['finalized_at'] != null) {
        throw FinalizedChartWeekFrozen(
          snapshot.chartType,
          snapshot.weekStartUtc,
        );
      }

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
  }

  @override
  Future<List<ChartEntityWeek>> finalizedWeeksFor(
    ChartType chartType,
    String entityId,
  ) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      '''
      SELECT e.*,
             s.week_start_utc AS snapshot_week_start_utc,
             s.week_end_utc AS snapshot_week_end_utc,
             s.finalized_at AS snapshot_finalized_at
      FROM ${DatabaseTables.chartEntries} e
      JOIN ${DatabaseTables.chartSnapshots} s ON s.id = e.chart_snapshot_id
      WHERE s.chart_type = ?
        AND s.finalized_at IS NOT NULL
        AND e.entity_id = ?
      ORDER BY s.week_start_utc ASC
      ''',
      [chartType.name, entityId],
    );
    return [
      for (final row in rows)
        ChartEntityWeek(
          weekStartUtc: DateTime.parse(
            row['snapshot_week_start_utc']! as String,
          ).toUtc(),
          weekEndUtc: DateTime.parse(
            row['snapshot_week_end_utc']! as String,
          ).toUtc(),
          finalizedAt: DateTime.parse(
            row['snapshot_finalized_at']! as String,
          ).toUtc(),
          entry: ChartEntryRowMapper.fromRow(row),
        ),
    ];
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
