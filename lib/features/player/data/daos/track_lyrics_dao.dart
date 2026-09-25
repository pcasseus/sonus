import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/models/track_lyrics.dart';
import '../mappers/track_lyrics_row_mapper.dart';

class TrackLyricsDao {
  const TrackLyricsDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert({
    required String songId,
    required String? plainText,
    required String? syncedText,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final row = TrackLyricsRowMapper.toRow(
      songId: songId,
      plainText: plainText,
      syncedText: syncedText,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    await db.rawInsert(
      '''
      INSERT INTO ${DatabaseTables.trackLyrics} (
        song_id,
        plain_text,
        synced_text,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(song_id) DO UPDATE SET
        plain_text = excluded.plain_text,
        synced_text = excluded.synced_text,
        updated_at = excluded.updated_at
      ''',
      [
        row['song_id'],
        row['plain_text'],
        row['synced_text'],
        row['created_at'],
        row['updated_at'],
      ],
    );
  }

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

  Future<void> deleteBySongId(String songId) async {
    await db.delete(
      DatabaseTables.trackLyrics,
      where: 'song_id = ?',
      whereArgs: [songId],
    );
  }
}
