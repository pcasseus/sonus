import '../../domain/models/track_lyrics.dart';
import '../../domain/services/lrc_parser.dart';

class TrackLyricsRowMapper {
  const TrackLyricsRowMapper._();

  static TrackLyrics fromRow(Map<String, Object?> row) {
    final syncedText = row['synced_text'] as String?;

    return TrackLyrics(
      songId: row['song_id']! as String,
      plainText: row['plain_text'] as String?,
      syncedLines: syncedText == null || syncedText.trim().isEmpty
          ? const []
          : LrcParser.parse(syncedText),
    );
  }
}
