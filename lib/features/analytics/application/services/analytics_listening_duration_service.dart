// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../models/analytics_listening_duration.dart';
import '../models/analytics_period.dart';
import '../models/analytics_time_window.dart';
import 'analytics_time_window_resolver.dart';

class AnalyticsListeningDurationService {
  const AnalyticsListeningDurationService({
    required PlaybackListeningSegmentRepository listeningSegments,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _listeningSegments = listeningSegments,
       _timeWindowResolver = timeWindowResolver;

  final PlaybackListeningSegmentRepository _listeningSegments;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<AnalyticsListeningDuration> load({
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

    var totalMilliseconds = 0;

    for (final segment in segments) {
      totalMilliseconds += _durationInsideWindow(
        segment: segment,
        window: window,
      ).inMilliseconds;
    }

    return AnalyticsListeningDuration(
      period: period,
      window: window,
      totalAudibleListeningDuration: Duration(milliseconds: totalMilliseconds),
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
