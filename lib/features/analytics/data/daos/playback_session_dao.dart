import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class PlaybackSessionDao {
  const PlaybackSessionDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Map<String, Object?> row) async {
    await db.insert(DatabaseTables.playbackSessions, row);
  }

  Future<void> update(Map<String, Object?> row) async {
    final id = row['id'] as String;

    final updated = await db.update(
      DatabaseTables.playbackSessions,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updated == 0) {
      throw StateError('Playback session not found: $id');
    }
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> findOpen() {
    return db.query(
      DatabaseTables.playbackSessions,
      where: 'ended_at IS NULL',
      orderBy: 'started_at ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> findAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];

    if (startedAtOrAfter != null) {
      clauses.add('started_at >= ?');
      args.add(startedAtOrAfter.toUtc().toIso8601String());
    }

    if (startedBefore != null) {
      clauses.add('started_at < ?');
      args.add(startedBefore.toUtc().toIso8601String());
    }

    return db.query(
      DatabaseTables.playbackSessions,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'started_at ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> findHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    DateTime? cursorStartedAt,
    String? cursorSessionId,
    required int limit,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
    }

    if ((cursorStartedAt == null) != (cursorSessionId == null)) {
      throw ArgumentError(
        'History cursor requires both startedAt and sessionId.',
      );
    }

    final clauses = <String>[];
    final args = <Object?>[];

    if (startedAtOrAfter != null) {
      clauses.add('started_at >= ?');
      args.add(startedAtOrAfter.toUtc().toIso8601String());
    }

    if (startedBefore != null) {
      clauses.add('started_at < ?');
      args.add(startedBefore.toUtc().toIso8601String());
    }

    if (cursorStartedAt != null && cursorSessionId != null) {
      final cursorTime = cursorStartedAt.toUtc().toIso8601String();

      clauses.add('(started_at < ? OR (started_at = ? AND id < ?))');

      args.add(cursorTime);
      args.add(cursorTime);
      args.add(cursorSessionId);
    }

    return db.query(
      DatabaseTables.playbackSessions,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
    );
  }
}
