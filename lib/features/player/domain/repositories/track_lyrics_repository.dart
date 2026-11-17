import '../models/track_lyrics.dart';

/// What playback reads. Lyrics are written only through the provenance
/// store (LyricsProvenanceWriter, App Update 1.3 v48), so no write here can
/// bypass the precedence rules that protect a listener's edits.
abstract interface class TrackLyricsRepository {
  Future<TrackLyrics?> getBySongId(String songId);
}
