import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

/// Song IDs from listening history, most recently started first, each once.
///
/// Read-only. Uses every recorded playback session, qualified or not, which
/// is what "recently played" means to a listener.
class RecentlyPlayedSongQuery {
  const RecentlyPlayedSongQuery(this._database);

  final DatabaseExecutor _database;

  Future<List<String>> songIds(int limit) async {
    if (limit <= 0) {
      return const [];
    }

    final rows = await _database.rawQuery(
      '''
      SELECT song_id
      FROM ${DatabaseTables.playbackSessions}
      GROUP BY song_id
      ORDER BY MAX(started_at) DESC, song_id ASC
      LIMIT ?
      ''',
      [limit],
    );

    return [for (final row in rows) row['song_id']! as String];
  }
}
