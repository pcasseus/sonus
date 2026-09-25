import '../../domain/models/track_lyrics.dart';
import '../../domain/repositories/track_lyrics_repository.dart';
import '../daos/track_lyrics_dao.dart';

class SqliteTrackLyricsRepository implements TrackLyricsRepository {
  const SqliteTrackLyricsRepository(this.dao);

  final TrackLyricsDao dao;

  @override
  Future<TrackLyrics?> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {
    final now = DateTime.now().toUtc();

    await dao.upsert(
      songId: songId,
      plainText: plainText,
      syncedText: syncedText,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> deleteBySongId(String songId) {
    return dao.deleteBySongId(songId);
  }
}
