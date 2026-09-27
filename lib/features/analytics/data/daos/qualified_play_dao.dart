import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

class QualifiedPlayDao {
  const QualifiedPlayDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Map<String, Object?> row) async {
    await db.insert(DatabaseTables.qualifiedPlays, row);
  }

  Future<void> update(Map<String, Object?> row) async {
    final id = row['id'];

    if (id is! String || id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Qualified play id must not be blank.',
      );
    }

    final updated = await db.update(
      DatabaseTables.qualifiedPlays,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updated != 1) {
      throw StateError('Qualified play not found: $id');
    }
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.qualifiedPlays,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, Object?>?> findByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    final rows = await db.query(
      DatabaseTables.qualifiedPlays,
      where: 'playback_session_id = ?',
      whereArgs: [playbackSessionId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> findByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final ids = playbackSessionIds.toSet().toList(growable: false);

    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(', ');

    return db.query(
      DatabaseTables.qualifiedPlays,
      where: 'playback_session_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'playback_session_id ASC',
    );
  }

  Future<List<Map<String, Object?>>> findAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];

    if (qualifiedAtOrAfter != null) {
      clauses.add('qualified_at >= ?');
      args.add(qualifiedAtOrAfter.toUtc().toIso8601String());
    }

    if (qualifiedBefore != null) {
      clauses.add('qualified_at < ?');
      args.add(qualifiedBefore.toUtc().toIso8601String());
    }

    return db.query(
      DatabaseTables.qualifiedPlays,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'qualified_at ASC, id ASC',
    );
  }
}
