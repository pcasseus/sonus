// ignore_for_file: prefer_initializing_formals

import '../../../domain/entities/playback_listening_segment.dart';
import '../../../domain/entities/qualified_play.dart';
import '../../../domain/repositories/playback_listening_segment_repository.dart';
import '../../../domain/repositories/qualified_play_repository.dart';
import '../../models/analytics_period.dart';
import '../../models/analytics_time_window.dart';
import '../../models/monthly_insights/monthly_daily_listening.dart';
import '../../models/monthly_insights/monthly_hourly_listening.dart';
import '../../models/monthly_insights/monthly_listening_distribution.dart';
import '../analytics_time_window_resolver.dart';

class MonthlyListeningDistributionService {
  const MonthlyListeningDistributionService({
    required QualifiedPlayRepository qualifiedPlays,
    required PlaybackListeningSegmentRepository listeningSegments,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _qualifiedPlays = qualifiedPlays,
       _listeningSegments = listeningSegments,
       _timeWindowResolver = timeWindowResolver;

  final QualifiedPlayRepository _qualifiedPlays;
  final PlaybackListeningSegmentRepository _listeningSegments;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<MonthlyListeningDistribution> load({
    required DateTime referenceLocal,
  }) async {
    final window = _timeWindowResolver.resolve(
      period: AnalyticsPeriod.month,
      referenceLocal: referenceLocal,
    );

    final playsFuture = _qualifiedPlays.getAll(
      qualifiedAtOrAfter: window.startUtc,
      qualifiedBefore: window.endUtc,
    );

    final segmentsFuture = _listeningSegments.getAll(
      startedBefore: window.endUtc,
    );

    final plays = await playsFuture;
    final segments = await segmentsFuture;

    final dayStreams = <DateTime, int>{};
    final hourStreams = <int, int>{};

    for (final play in plays) {
      _countQualifiedPlay(
        play: play,
        dayStreams: dayStreams,
        hourStreams: hourStreams,
      );
    }

    final dayMilliseconds = <DateTime, int>{};
    final hourMilliseconds = <int, int>{};

    for (final segment in segments) {
      _distributeSegment(
        segment: segment,
        window: window,
        dayMilliseconds: dayMilliseconds,
        hourMilliseconds: hourMilliseconds,
      );
    }

    final monthStart = DateTime(referenceLocal.year, referenceLocal.month);

    final monthEnd = DateTime(referenceLocal.year, referenceLocal.month + 1);

    final days = <MonthlyDailyListening>[];

    var day = monthStart;

    while (day.isBefore(monthEnd)) {
      final key = DateTime(day.year, day.month, day.day);

      days.add(
        MonthlyDailyListening(
          localDate: key,
          streams: dayStreams[key] ?? 0,
          listeningDuration: Duration(milliseconds: dayMilliseconds[key] ?? 0),
        ),
      );

      day = DateTime(day.year, day.month, day.day + 1);
    }

    final hours = List<MonthlyHourlyListening>.generate(
      24,
      (hour) => MonthlyHourlyListening(
        hour: hour,
        streams: hourStreams[hour] ?? 0,
        listeningDuration: Duration(milliseconds: hourMilliseconds[hour] ?? 0),
      ),
      growable: false,
    );

    return MonthlyListeningDistribution(
      days: List.unmodifiable(days),
      hours: List.unmodifiable(hours),
    );
  }

  void _countQualifiedPlay({
    required QualifiedPlay play,
    required Map<DateTime, int> dayStreams,
    required Map<int, int> hourStreams,
  }) {
    final local = play.qualifiedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);

    dayStreams.update(day, (current) => current + 1, ifAbsent: () => 1);

    hourStreams.update(local.hour, (current) => current + 1, ifAbsent: () => 1);
  }

  void _distributeSegment({
    required PlaybackListeningSegment segment,
    required AnalyticsTimeWindow window,
    required Map<DateTime, int> dayMilliseconds,
    required Map<int, int> hourMilliseconds,
  }) {
    var startUtc = segment.startedAt.toUtc();
    var endUtc = _truthfulEndpoint(segment);

    final windowStart = window.startUtc;
    final windowEnd = window.endUtc;

    if (windowStart != null && startUtc.isBefore(windowStart)) {
      startUtc = windowStart;
    }

    if (windowEnd != null && endUtc.isAfter(windowEnd)) {
      endUtc = windowEnd;
    }

    if (!endUtc.isAfter(startUtc)) {
      return;
    }

    var cursorUtc = startUtc;

    while (cursorUtc.isBefore(endUtc)) {
      final cursorLocal = cursorUtc.toLocal();

      final nextLocalHour = DateTime(
        cursorLocal.year,
        cursorLocal.month,
        cursorLocal.day,
        cursorLocal.hour + 1,
      );

      final nextBoundaryUtc = nextLocalHour.toUtc();

      final sliceEndUtc = nextBoundaryUtc.isBefore(endUtc)
          ? nextBoundaryUtc
          : endUtc;

      if (!sliceEndUtc.isAfter(cursorUtc)) {
        break;
      }

      final duration = sliceEndUtc.difference(cursorUtc);

      final dayKey = DateTime(
        cursorLocal.year,
        cursorLocal.month,
        cursorLocal.day,
      );

      dayMilliseconds.update(
        dayKey,
        (current) => current + duration.inMilliseconds,
        ifAbsent: () => duration.inMilliseconds,
      );

      hourMilliseconds.update(
        cursorLocal.hour,
        (current) => current + duration.inMilliseconds,
        ifAbsent: () => duration.inMilliseconds,
      );

      cursorUtc = sliceEndUtc;
    }
  }

  DateTime _truthfulEndpoint(PlaybackListeningSegment segment) {
    final endedAt = segment.endedAt;

    if (endedAt != null) {
      return endedAt.toUtc();
    }

    if (segment.listenedDuration <= Duration.zero) {
      return segment.startedAt.toUtc();
    }

    return segment.startedAt.toUtc().add(segment.listenedDuration);
  }
}
