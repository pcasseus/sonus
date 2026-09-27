import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class PlaybackListeningSegmentDao {
  const PlaybackListeningSegmentDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Map<String, Object?> row) async {
    await db.insert(DatabaseTables.playbackListeningSegments, row);
  }

  Future<void> update(Map<String, Object?> row) async {
    final id = row['id'] as String;

    final updated = await db.update(
      DatabaseTables.playbackListeningSegments,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updated == 0) {
      throw StateError('Playback listening segment not found: $id');
    }
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.playbackListeningSegments,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, Object?>?> findOpenForSession(
    String playbackSessionId,
  ) async {
    final rows = await db.query(
      DatabaseTables.playbackListeningSegments,
      where: 'playback_session_id = ? AND ended_at IS NULL',
      whereArgs: [playbackSessionId],
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> findForSession(String playbackSessionId) {
    return db.query(
      DatabaseTables.playbackListeningSegments,
      where: 'playback_session_id = ?',
      whereArgs: [playbackSessionId],
      orderBy: 'started_at ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> findAll({DateTime? startedBefore}) async {
    return db.query(
      DatabaseTables.playbackListeningSegments,
      where: startedBefore == null ? null : 'started_at < ?',
      whereArgs: startedBefore == null
          ? null
          : [startedBefore.toUtc().toIso8601String()],
      orderBy: 'started_at ASC, id ASC',
    );
  }
}
