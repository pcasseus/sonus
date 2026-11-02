import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_tables.dart';
import '../../analytics/application/services/pulse/pulse_listening_records.dart';
import '../application/song_listening_records.dart';

/// Song Stats' read-only queries. Served by the existing
/// (song_id, started_at) and (song_id, qualified_at) indexes; no schema
/// change and no writes.
class SqliteSongListeningRecords implements SongListeningRecords {
  const SqliteSongListeningRecords(this._db);

  final DatabaseExecutor _db;

  @override
  Future<List<PulseSegmentRecord>> segmentsForSong(String songId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT seg.started_at, seg.ended_at, seg.listened_duration_ms,
             s.song_id, s.artist_id, s.album_id
      FROM ${DatabaseTables.playbackSessions} s
      JOIN ${DatabaseTables.playbackListeningSegments} seg
        ON seg.playback_session_id = s.id
      WHERE s.song_id = ?
      ''',
      [songId],
    );
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
  Future<List<PulsePlayRecord>> qualifiedPlaysForSong(String songId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT qualified_at AS at, song_id, artist_id, album_id
      FROM ${DatabaseTables.qualifiedPlays}
      WHERE song_id = ?
      ''',
      [songId],
    );
    return rows.map(_play).toList();
  }

  @override
  Future<List<PulsePlayRecord>> audibleSessionsForSong(String songId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT started_at AS at, song_id, artist_id, album_id
      FROM ${DatabaseTables.playbackSessions}
      WHERE song_id = ? AND listened_duration_ms > 0
      ''',
      [songId],
    );
    return rows.map(_play).toList();
  }

  @override
  Future<SongPlayedIdentity?> lastPlayedIdentity(String songId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT song_title, artist_name, album_title
      FROM ${DatabaseTables.playbackSessions}
      WHERE song_id = ?
      ORDER BY started_at DESC
      LIMIT 1
      ''',
      [songId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SongPlayedIdentity(
      title: row['song_title']! as String,
      artistName: row['artist_name']! as String,
      albumTitle: row['album_title']! as String,
    );
  }

  @override
  Future<DateTime?> firstSessionStartedAt() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(started_at) AS first '
      'FROM ${DatabaseTables.playbackSessions}',
    );
    final value = rows.isEmpty ? null : rows.single['first'];
    return value is String ? DateTime.parse(value).toUtc() : null;
  }

  PulsePlayRecord _play(Map<String, Object?> row) => PulsePlayRecord(
    at: DateTime.parse(row['at']! as String).toUtc(),
    songId: row['song_id']! as String,
    artistId: row['artist_id']! as String,
    albumId: row['album_id']! as String,
  );
}
