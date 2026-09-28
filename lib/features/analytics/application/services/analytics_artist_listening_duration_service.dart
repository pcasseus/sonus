// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/entities/playback_session.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../models/analytics_period.dart';
import '../models/analytics_time_window.dart';
import 'analytics_time_window_resolver.dart';

class AnalyticsArtistListeningDurationService {
  const AnalyticsArtistListeningDurationService({
    required PlaybackSessionRepository playbackSessions,
    required PlaybackListeningSegmentRepository listeningSegments,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _playbackSessions = playbackSessions,
       _listeningSegments = listeningSegments,
       _timeWindowResolver = timeWindowResolver;

  final PlaybackSessionRepository _playbackSessions;
  final PlaybackListeningSegmentRepository _listeningSegments;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<Map<String, Duration>> load({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
  }) async {
    final window = _timeWindowResolver.resolve(
      period: period,
      referenceLocal: referenceLocal,
    );

    final segments = await _listeningSegments.getAll(
      startedBefore: window.endUtc,
    );

    final sessionCache = <String, PlaybackSession?>{};
    final totalsMilliseconds = <String, int>{};

    for (final segment in segments) {
      final duration = _durationInsideWindow(segment: segment, window: window);

      if (duration <= Duration.zero) {
        continue;
      }

      final sessionId = segment.playbackSessionId;

      if (!sessionCache.containsKey(sessionId)) {
        sessionCache[sessionId] = await _playbackSessions.getById(sessionId);
      }

      final session = sessionCache[sessionId];

      if (session == null) {
        continue;
      }

      totalsMilliseconds.update(
        session.artistId,
        (current) => current + duration.inMilliseconds,
        ifAbsent: () => duration.inMilliseconds,
      );
    }

    return Map<String, Duration>.unmodifiable(
      totalsMilliseconds.map(
        (artistId, milliseconds) =>
            MapEntry(artistId, Duration(milliseconds: milliseconds)),
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
