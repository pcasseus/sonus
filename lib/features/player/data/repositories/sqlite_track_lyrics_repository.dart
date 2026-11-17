import '../../domain/models/track_lyrics.dart';
import '../../domain/repositories/track_lyrics_repository.dart';
import '../daos/track_lyrics_dao.dart';

/// Reads stored lyrics for playback. Writes go through the provenance store.
class SqliteTrackLyricsRepository implements TrackLyricsRepository {
  const SqliteTrackLyricsRepository(this.dao);

  final TrackLyricsDao dao;

  @override
  Future<TrackLyrics?> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }
}
