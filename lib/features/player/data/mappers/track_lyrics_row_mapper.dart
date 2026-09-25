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

  static Map<String, Object?> toRow({
    required String songId,
    required String? plainText,
    required String? syncedText,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return <String, Object?>{
      'song_id': songId,
      'plain_text': plainText,
      'synced_text': syncedText,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
