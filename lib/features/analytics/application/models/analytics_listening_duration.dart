import 'analytics_period.dart';
import 'analytics_time_window.dart';

class AnalyticsListeningDuration {
  const AnalyticsListeningDuration({
    required this.period,
    required this.window,
    required this.totalAudibleListeningDuration,
  });

  final AnalyticsPeriod period;
  final AnalyticsTimeWindow window;

  final Duration totalAudibleListeningDuration;

  bool get hasListening => totalAudibleListeningDuration > Duration.zero;
}
