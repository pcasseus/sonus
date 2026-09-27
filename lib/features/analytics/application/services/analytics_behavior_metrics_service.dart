// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/playback_session.dart';
import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../models/analytics_behavior_metrics.dart';
import '../models/analytics_peak_day.dart';
import '../models/analytics_period.dart';
import '../models/analytics_time_window.dart';
import 'analytics_time_window_resolver.dart';

class AnalyticsBehaviorMetricsService {
  const AnalyticsBehaviorMetricsService({
    required PlaybackSessionRepository playbackSessions,
    required QualifiedPlayRepository qualifiedPlays,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _playbackSessions = playbackSessions,
       _qualifiedPlays = qualifiedPlays,
       _timeWindowResolver = timeWindowResolver;

  final PlaybackSessionRepository _playbackSessions;
  final QualifiedPlayRepository _qualifiedPlays;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<AnalyticsBehaviorMetrics> load({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
  }) async {
    final window = _timeWindowResolver.resolve(
      period: period,
      referenceLocal: referenceLocal,
    );

    final sessionsFuture = _playbackSessions.getAll(
      startedAtOrAfter: window.startUtc,
      startedBefore: window.endUtc,
    );

    final playsFuture = _qualifiedPlays.getAll(
      qualifiedAtOrAfter: window.startUtc,
      qualifiedBefore: window.endUtc,
    );

    final sessions = await sessionsFuture;
    final plays = await playsFuture;

    return _build(
      period: period,
      window: window,
      referenceLocal: referenceLocal,
      sessions: sessions,
      plays: plays,
    );
  }

  AnalyticsBehaviorMetrics _build({
    required AnalyticsPeriod period,
    required AnalyticsTimeWindow window,
    required DateTime referenceLocal,
    required List<PlaybackSession> sessions,
    required List<QualifiedPlay> plays,
  }) {
    var endedSessionCount = 0;

    var completedSessionCount = 0;
    var skippedSessionCount = 0;
    var stoppedSessionCount = 0;
    var replacedSessionCount = 0;
    var interruptedSessionCount = 0;
    var failedSessionCount = 0;

    DateTime? firstSessionStartedAt;
    DateTime? lastSessionStartedAt;

    for (final session in sessions) {
      final startedAt = session.startedAt.toUtc();

      if (firstSessionStartedAt == null ||
          startedAt.isBefore(firstSessionStartedAt)) {
        firstSessionStartedAt = startedAt;
      }

      if (lastSessionStartedAt == null ||
          startedAt.isAfter(lastSessionStartedAt)) {
        lastSessionStartedAt = startedAt;
      }

      final reason = session.endReason;

      if (!session.isEnded || reason == null) {
        continue;
      }

      endedSessionCount++;

      switch (reason) {
        case PlaybackSessionEndReason.completed:
          completedSessionCount++;
          break;

        case PlaybackSessionEndReason.skipped:
          skippedSessionCount++;
          break;

        case PlaybackSessionEndReason.stopped:
          stoppedSessionCount++;
          break;

        case PlaybackSessionEndReason.replaced:
          replacedSessionCount++;
          break;

        case PlaybackSessionEndReason.interrupted:
          interruptedSessionCount++;
          break;

        case PlaybackSessionEndReason.failed:
          failedSessionCount++;
          break;
      }
    }

    final qualifiedByLocalDay = <DateTime, int>{};

    for (final play in plays) {
      final local = play.qualifiedAt.toLocal();

      final localDate = DateTime(local.year, local.month, local.day);

      qualifiedByLocalDay.update(
        localDate,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    AnalyticsPeakDay? peakDay;

    for (final entry in qualifiedByLocalDay.entries) {
      final currentPeak = peakDay;

      if (currentPeak == null ||
          entry.value > currentPeak.qualifiedStreamCount ||
          (entry.value == currentPeak.qualifiedStreamCount &&
              entry.key.isBefore(currentPeak.localDate))) {
        peakDay = AnalyticsPeakDay(
          localDate: entry.key,
          qualifiedStreamCount: entry.value,
        );
      }
    }

    final activeQualifiedDayCount = qualifiedByLocalDay.length;

    final averageQualifiedStreamsPerActiveDay = activeQualifiedDayCount == 0
        ? 0.0
        : plays.length / activeQualifiedDayCount;

    final calendarDayCount = _calendarDayCount(
      period: period,
      referenceLocal: referenceLocal,
      qualifiedByLocalDay: qualifiedByLocalDay,
    );

    final averageQualifiedStreamsPerCalendarDay =
        plays.isEmpty || calendarDayCount == 0
        ? 0.0
        : plays.length / calendarDayCount;

    return AnalyticsBehaviorMetrics(
      period: period,
      window: window,
      sessionCount: sessions.length,
      endedSessionCount: endedSessionCount,
      completedSessionCount: completedSessionCount,
      skippedSessionCount: skippedSessionCount,
      stoppedSessionCount: stoppedSessionCount,
      replacedSessionCount: replacedSessionCount,
      interruptedSessionCount: interruptedSessionCount,
      failedSessionCount: failedSessionCount,
      firstSessionStartedAt: firstSessionStartedAt,
      lastSessionStartedAt: lastSessionStartedAt,
      activeQualifiedDayCount: activeQualifiedDayCount,
      averageQualifiedStreamsPerActiveDay: averageQualifiedStreamsPerActiveDay,
      averageQualifiedStreamsPerCalendarDay:
          averageQualifiedStreamsPerCalendarDay,
      peakDay: peakDay,
    );
  }

  int _calendarDayCount({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
    required Map<DateTime, int> qualifiedByLocalDay,
  }) {
    switch (period) {
      case AnalyticsPeriod.day:
        return 1;

      case AnalyticsPeriod.week:
        return 7;

      case AnalyticsPeriod.month:
        final start = DateTime.utc(referenceLocal.year, referenceLocal.month);

        final end = DateTime.utc(referenceLocal.year, referenceLocal.month + 1);

        return end.difference(start).inDays;

      case AnalyticsPeriod.year:
        final start = DateTime.utc(referenceLocal.year);
        final end = DateTime.utc(referenceLocal.year + 1);

        return end.difference(start).inDays;

      case AnalyticsPeriod.lifetime:
        if (qualifiedByLocalDay.isEmpty) {
          return 0;
        }

        var firstQualifiedLocalDay = qualifiedByLocalDay.keys.first;

        for (final localDay in qualifiedByLocalDay.keys.skip(1)) {
          if (localDay.isBefore(firstQualifiedLocalDay)) {
            firstQualifiedLocalDay = localDay;
          }
        }

        final referenceLocalDay = DateTime(
          referenceLocal.year,
          referenceLocal.month,
          referenceLocal.day,
        );

        if (firstQualifiedLocalDay.isAfter(referenceLocalDay)) {
          return 1;
        }

        final firstUtcDate = DateTime.utc(
          firstQualifiedLocalDay.year,
          firstQualifiedLocalDay.month,
          firstQualifiedLocalDay.day,
        );

        final referenceUtcDate = DateTime.utc(
          referenceLocalDay.year,
          referenceLocalDay.month,
          referenceLocalDay.day,
        );

        return referenceUtcDate.difference(firstUtcDate).inDays + 1;
    }
  }
}
