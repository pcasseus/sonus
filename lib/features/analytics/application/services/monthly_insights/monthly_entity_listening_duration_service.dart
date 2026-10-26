// ignore_for_file: prefer_initializing_formals

import '../../../domain/entities/playback_listening_segment.dart';
import '../../../domain/entities/playback_session.dart';
import '../../../domain/repositories/playback_listening_segment_repository.dart';
import '../../../domain/repositories/playback_session_repository.dart';
import '../../models/analytics_period.dart';
import '../../models/analytics_time_window.dart';
import '../../models/monthly_insights/monthly_entity_listening_durations.dart';
import '../analytics_time_window_resolver.dart';
import '../listening_artist_attribution.dart';

class MonthlyEntityListeningDurationService {
  const MonthlyEntityListeningDurationService({
    required PlaybackSessionRepository playbackSessions,
    required PlaybackListeningSegmentRepository listeningSegments,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
    ListeningArtistAttribution? artistAttribution,
  }) : _playbackSessions = playbackSessions,
       _listeningSegments = listeningSegments,
       _timeWindowResolver = timeWindowResolver,
       _artistAttribution = artistAttribution;

  final PlaybackSessionRepository _playbackSessions;
  final PlaybackListeningSegmentRepository _listeningSegments;
  final AnalyticsTimeWindowResolver _timeWindowResolver;
  final ListeningArtistAttribution? _artistAttribution;

  Future<MonthlyEntityListeningDurations> load({
    required DateTime referenceLocal,
  }) async {
    final window = _timeWindowResolver.resolve(
      period: AnalyticsPeriod.month,
      referenceLocal: referenceLocal,
    );

    final segments = await _listeningSegments.getAll(
      startedBefore: window.endUtc,
    );

    final overlapping = <_SegmentDuration>[];

    for (final segment in segments) {
      final duration = _durationInsideWindow(segment: segment, window: window);

      if (duration <= Duration.zero) {
        continue;
      }

      overlapping.add(_SegmentDuration(segment: segment, duration: duration));
    }

    if (overlapping.isEmpty) {
      return const MonthlyEntityListeningDurations(
        songs: {},
        artists: {},
        albums: {},
      );
    }

    final sessionIds = overlapping
        .map((entry) => entry.segment.playbackSessionId)
        .toSet();

    final sessions = await _playbackSessions.getByIds(sessionIds);

    final sessionsById = <String, PlaybackSession>{
      for (final session in sessions) session.id: session,
    };

    final attributor = await ArtistAttributor.of(_artistAttribution);
    final songMilliseconds = <String, int>{};
    final artistMilliseconds = <String, int>{};
    final albumMilliseconds = <String, int>{};

    for (final entry in overlapping) {
      final session = sessionsById[entry.segment.playbackSessionId];

      if (session == null) {
        continue;
      }

      _addDuration(
        totals: songMilliseconds,
        entityId: session.songId,
        duration: entry.duration,
      );

      _addDuration(
        totals: artistMilliseconds,
        entityId: attributor.artistFor(
          artistId: session.artistId,
          albumId: session.albumId,
        ),
        duration: entry.duration,
      );

      _addDuration(
        totals: albumMilliseconds,
        entityId: session.albumId,
        duration: entry.duration,
      );
    }

    return MonthlyEntityListeningDurations(
      songs: _toDurationMap(songMilliseconds),
      artists: _toDurationMap(artistMilliseconds),
      albums: _toDurationMap(albumMilliseconds),
    );
  }

  void _addDuration({
    required Map<String, int> totals,
    required String entityId,
    required Duration duration,
  }) {
    totals.update(
      entityId,
      (current) => current + duration.inMilliseconds,
      ifAbsent: () => duration.inMilliseconds,
    );
  }

  Map<String, Duration> _toDurationMap(Map<String, int> millisecondsById) {
    return Map<String, Duration>.unmodifiable(
      millisecondsById.map(
        (entityId, milliseconds) =>
            MapEntry(entityId, Duration(milliseconds: milliseconds)),
      ),
    );
  }

  Duration _durationInsideWindow({
    required PlaybackListeningSegment segment,
    required AnalyticsTimeWindow window,
  }) {
    final segmentStart = segment.startedAt.toUtc();
    final segmentEnd = _truthfulEndpoint(segment);

    if (!segmentEnd.isAfter(segmentStart)) {
      return Duration.zero;
    }

    var overlapStart = segmentStart;
    var overlapEnd = segmentEnd;

    final windowStart = window.startUtc;
    final windowEnd = window.endUtc;

    if (windowStart != null && overlapStart.isBefore(windowStart)) {
      overlapStart = windowStart;
    }

    if (windowEnd != null && overlapEnd.isAfter(windowEnd)) {
      overlapEnd = windowEnd;
    }

    if (!overlapEnd.isAfter(overlapStart)) {
      return Duration.zero;
    }

    return overlapEnd.difference(overlapStart);
  }

  DateTime _truthfulEndpoint(PlaybackListeningSegment segment) {
    final endedAt = segment.endedAt;

    if (endedAt != null) {
      return endedAt.toUtc();
    }

    final listenedDuration = segment.listenedDuration;

    if (listenedDuration <= Duration.zero) {
      return segment.startedAt.toUtc();
    }

    return segment.startedAt.toUtc().add(listenedDuration);
  }
}

class _SegmentDuration {
  const _SegmentDuration({required this.segment, required this.duration});

  final PlaybackListeningSegment segment;
  final Duration duration;
}
