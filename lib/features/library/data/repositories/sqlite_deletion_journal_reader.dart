import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

/// Reads the App Update 1.2 deletion journal for the chart engines.
///
/// D5 (approved 2026-11-07): a deletion never invents a story. Chart weeks
/// recalculated after a permanent deletion publish no new Moments, and no
/// play from before the latest deletion (or a merge that moved plays) may
/// create one.
class SqliteDeletionJournalReader {
  const SqliteDeletionJournalReader(this._db);

  final Future<DatabaseExecutor> Function() _db;

  /// No Moment may be created from a play before this instant.
  Future<DateTime?> momentsCutoff() async {
    final db = await _db();
    DateTime? latest;
    for (final row in await db.query(
      DatabaseTables.libraryDeletionJournal,
      columns: ['operation', 'summary', 'committed_at'],
    )) {
      if (row['operation'] == 'duplicateMerge') {
        final summary = jsonDecode(row['summary']! as String) as Map;
        if (((summary['movedPlays'] as num?) ?? 0) == 0) continue;
      }
      final at = DateTime.tryParse(row['committed_at']! as String)?.toUtc();
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  /// Every recalculated week, as `chartType:weekStartUtc`.
  Future<Set<String>> recalculatedWeeks() async {
    final db = await _db();
    return {
      for (final row in await db.query(
        DatabaseTables.libraryDeletionJournal,
        columns: ['rebuilt_weeks'],
        where: "operation = 'userDeletion'",
      ))
        ...(jsonDecode(row['rebuilt_weeks']! as String) as List).cast<String>(),
    };
  }

  /// Whether the [chartType] week starting at [weekStartUtc] was
  /// recalculated after a deletion (so it publishes no new Moments).
  Future<bool> isRecalculatedWeek(
    String chartType,
    DateTime weekStartUtc,
  ) async {
    final key = '$chartType:${weekStartUtc.toUtc().toIso8601String()}';
    final db = await _db();
    for (final row in await db.query(
      DatabaseTables.libraryDeletionJournal,
      columns: ['rebuilt_weeks'],
      where: "operation = 'userDeletion'",
    )) {
      final weeks = (jsonDecode(row['rebuilt_weeks']! as String) as List)
          .cast<String>();
      if (weeks.contains(key)) return true;
    }
    return false;
  }
}
