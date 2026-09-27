import 'analytics_peak_day.dart';
import 'analytics_period.dart';
import 'analytics_time_window.dart';

class AnalyticsBehaviorMetrics {
  const AnalyticsBehaviorMetrics({
    required this.period,
    required this.window,
    required this.sessionCount,
    required this.endedSessionCount,
    required this.completedSessionCount,
    required this.skippedSessionCount,
    required this.stoppedSessionCount,
    required this.replacedSessionCount,
    required this.interruptedSessionCount,
    required this.failedSessionCount,
    required this.firstSessionStartedAt,
    required this.lastSessionStartedAt,
    required this.activeQualifiedDayCount,
    required this.averageQualifiedStreamsPerActiveDay,
    required this.averageQualifiedStreamsPerCalendarDay,
    required this.peakDay,
  });

  final AnalyticsPeriod period;
  final AnalyticsTimeWindow window;

  final int sessionCount;
  final int endedSessionCount;

  final int completedSessionCount;
  final int skippedSessionCount;
  final int stoppedSessionCount;
  final int replacedSessionCount;
  final int interruptedSessionCount;
  final int failedSessionCount;

  final DateTime? firstSessionStartedAt;
  final DateTime? lastSessionStartedAt;

  final int activeQualifiedDayCount;
  final double averageQualifiedStreamsPerActiveDay;
  final double averageQualifiedStreamsPerCalendarDay;

  final AnalyticsPeakDay? peakDay;

  double get completionRate {
    if (endedSessionCount == 0) {
      return 0;
    }

    return completedSessionCount / endedSessionCount;
  }

  double get skipRate {
    if (endedSessionCount == 0) {
      return 0;
    }

    return skippedSessionCount / endedSessionCount;
  }
}
