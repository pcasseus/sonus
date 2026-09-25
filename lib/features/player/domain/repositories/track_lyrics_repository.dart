import '../models/track_lyrics.dart';

abstract interface class TrackLyricsRepository {
  Future<TrackLyrics?> getBySongId(String songId);

  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  });

  Future<void> deleteBySongId(String songId);
}
