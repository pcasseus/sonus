import '../../analytics/application/services/pulse/pulse_listening_records.dart';

/// The name a song was last played under: kept for songs no longer in the
/// library, never invented.
class SongPlayedIdentity {
  const SongPlayedIdentity({
    required this.title,
    required this.artistName,
    required this.albumTitle,
  });

  final String title;
  final String artistName;
  final String albumTitle;
}

/// Read-only listening history for one song, with the same record types
/// and rules as Sonus Pulse: minutes come from listening segments, streams
/// from qualified plays, all plays from sessions with audible time.
abstract interface class SongListeningRecords {
  /// Every listening segment of [songId]'s sessions.
  Future<List<PulseSegmentRecord>> segmentsForSong(String songId);

  /// Every qualified play of [songId] (at = qualified time).
  Future<List<PulsePlayRecord>> qualifiedPlaysForSong(String songId);

  /// Every session of [songId] with audible time (at = start time).
  Future<List<PulsePlayRecord>> audibleSessionsForSong(String songId);

  /// The song's identity from its most recent session, or null.
  Future<SongPlayedIdentity?> lastPlayedIdentity(String songId);

  /// The start of the earliest recorded session of any song, or null.
  Future<DateTime?> firstSessionStartedAt();
}
