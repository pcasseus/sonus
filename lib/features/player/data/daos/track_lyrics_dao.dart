import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/models/track_lyrics.dart';
import '../mappers/track_lyrics_row_mapper.dart';

/// Reads `track_lyrics` for playback. It has no writer: lyrics are written
/// only through the provenance store (App Update 1.3 v48).
class TrackLyricsDao {
  const TrackLyricsDao(this.db);

  final DatabaseExecutor db;

  Future<TrackLyrics?> findBySongId(String songId) async {
    final rows = await db.query(
      DatabaseTables.trackLyrics,
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return TrackLyricsRowMapper.fromRow(rows.single);
  }
}
