import '../../models/analytics_time_window.dart';

/// One stretch of audible playback with the identity of what was playing.
class PulseSegmentRecord {
  const PulseSegmentRecord({
    required this.startedAt,
    required this.endedAt,
    required this.listenedDuration,
    required this.songId,
    required this.artistId,
    required this.albumId,
  });

  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration listenedDuration;
  final String songId;
  final String artistId;
  final String albumId;

  /// Where the segment really ends: its end time, or, while still open,
  /// its start plus the time recorded so far (the existing rule).
  DateTime get truthfulEnd {
    final ended = endedAt;
    if (ended != null) return ended.toUtc();
    if (listenedDuration <= Duration.zero) return startedAt.toUtc();
    return startedAt.toUtc().add(listenedDuration);
  }
}

/// One counted moment: a qualified play (at [at] = qualified time) or an
/// audible session (at [at] = start time).
class PulsePlayRecord {
  const PulsePlayRecord({
    required this.at,
    required this.songId,
    required this.artistId,
    required this.albumId,
  });

  final DateTime at;
  final String songId;
  final String artistId;
  final String albumId;
}

/// Read-only listening history for Sonus Pulse. Every query is bounded on
/// both sides of the window, so year and multi-year views never read all of
/// history. Results may include rows just outside the window; the caller
/// clips them exactly.
abstract interface class PulseListeningRecords {
  /// The start of the earliest recorded session, or null.
  Future<DateTime?> firstSessionStartedAt();

  /// Segments that may overlap [window], with their session's identity.
  Future<List<PulseSegmentRecord>> segmentsOverlapping(
    AnalyticsTimeWindow window,
  );

  /// Qualified plays around [window].
  Future<List<PulsePlayRecord>> qualifiedPlays(AnalyticsTimeWindow window);

  /// Sessions with audible time (listened > 0) that started around [window].
  Future<List<PulsePlayRecord>> audibleSessions(AnalyticsTimeWindow window);
}
