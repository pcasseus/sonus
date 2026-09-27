import 'analytics_period.dart';
import 'analytics_time_window.dart';

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.period,
    required this.window,
    required this.qualifiedStreamCount,
    required this.qualifiedListeningDuration,
    required this.distinctSongCount,
    required this.distinctArtistCount,
    required this.distinctAlbumCount,
    required this.firstQualifiedAt,
    required this.lastQualifiedAt,
  });

  final AnalyticsPeriod period;
  final AnalyticsTimeWindow window;

  final int qualifiedStreamCount;
  final Duration qualifiedListeningDuration;

  final int distinctSongCount;
  final int distinctArtistCount;
  final int distinctAlbumCount;

  final DateTime? firstQualifiedAt;
  final DateTime? lastQualifiedAt;

  bool get hasListening => qualifiedStreamCount > 0;
}
