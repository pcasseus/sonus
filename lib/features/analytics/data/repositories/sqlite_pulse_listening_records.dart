import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../application/models/analytics_time_window.dart';
import '../../application/services/pulse/pulse_listening_records.dart';

/// Pulse's read-only queries over listening history. No schema change: the
/// started_at / ended_at / qualified_at indexes serve every bound.
///
/// Times are stored as ISO-8601 UTC strings whose fraction length varies, so
/// string comparison can misorder instants within one second. Each bound is
/// widened by [_margin] and the service clips exactly in Dart.
class SqlitePulseListeningRecords implements PulseListeningRecords {
  const SqlitePulseListeningRecords(this._db);

  final DatabaseExecutor _db;

  static const _margin = Duration(seconds: 2);

  @override
  Future<DateTime?> firstSessionStartedAt() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(started_at) AS first FROM ${DatabaseTables.playbackSessions}',
    );
    final value = rows.isEmpty ? null : rows.single['first'];
    return value is String ? DateTime.parse(value).toUtc() : null;
  }

  @override
  Future<List<PulseSegmentRecord>> segmentsOverlapping(
    AnalyticsTimeWindow window,
  ) async {
    final (where, args) = _bounds(
      window,
      // Segments reach into the window from before: bound by their end.
      // Open segments (no end yet) are kept and clipped by the service.
      lowerColumn: 'seg.ended_at',
      lowerAllowsNull: true,
      upperColumn: 'seg.started_at',
    );
    final rows = await _db.rawQuery('''
      SELECT seg.started_at, seg.ended_at, seg.listened_duration_ms,
             s.song_id, s.artist_id, s.album_id
      FROM ${DatabaseTables.playbackListeningSegments} seg
      JOIN ${DatabaseTables.playbackSessions} s
        ON s.id = seg.playback_session_id
      $where
    ''', args);
    return [
      for (final row in rows)
        PulseSegmentRecord(
          startedAt: DateTime.parse(row['started_at']! as String).toUtc(),
          endedAt: switch (row['ended_at']) {
            final String value => DateTime.parse(value).toUtc(),
            _ => null,
          },
          listenedDuration: Duration(
            milliseconds: (row['listened_duration_ms'] as int?) ?? 0,
          ),
          songId: row['song_id']! as String,
          artistId: row['artist_id']! as String,
          albumId: row['album_id']! as String,
        ),
    ];
  }

  @override
  Future<List<PulsePlayRecord>> qualifiedPlays(
    AnalyticsTimeWindow window,
  ) async {
    final (where, args) = _bounds(
      window,
      lowerColumn: 'qualified_at',
      upperColumn: 'qualified_at',
    );
    final rows = await _db.rawQuery('''
      SELECT qualified_at AS at, song_id, artist_id, album_id
      FROM ${DatabaseTables.qualifiedPlays}
      $where
    ''', args);
    return rows.map(_play).toList();
  }

  @override
  Future<List<PulsePlayRecord>> audibleSessions(
    AnalyticsTimeWindow window,
  ) async {
    final (where, args) = _bounds(
      window,
      lowerColumn: 'started_at',
      upperColumn: 'started_at',
      extra: 'listened_duration_ms > 0',
    );
    final rows = await _db.rawQuery('''
      SELECT started_at AS at, song_id, artist_id, album_id
      FROM ${DatabaseTables.playbackSessions}
      $where
    ''', args);
    return rows.map(_play).toList();
  }

  PulsePlayRecord _play(Map<String, Object?> row) => PulsePlayRecord(
    at: DateTime.parse(row['at']! as String).toUtc(),
    songId: row['song_id']! as String,
    artistId: row['artist_id']! as String,
    albumId: row['album_id']! as String,
  );

  (String, List<Object?>) _bounds(
    AnalyticsTimeWindow window, {
    required String lowerColumn,
    required String upperColumn,
    bool lowerAllowsNull = false,
    String? extra,
  }) {
    final clauses = <String>[];
    final args = <Object?>[];
    final start = window.startUtc;
    final end = window.endUtc;
    if (start != null) {
      final bound = '$lowerColumn >= ?';
      clauses.add(lowerAllowsNull ? '($lowerColumn IS NULL OR $bound)' : bound);
      args.add(start.toUtc().subtract(_margin).toIso8601String());
    }
    if (end != null) {
      clauses.add('$upperColumn < ?');
      args.add(end.toUtc().add(_margin).toIso8601String());
    }
    if (extra != null) clauses.add(extra);
    return (clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }
}
