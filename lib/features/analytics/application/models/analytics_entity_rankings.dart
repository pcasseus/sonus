import 'analytics_period.dart';
import 'analytics_ranked_entity.dart';
import 'analytics_time_window.dart';

class AnalyticsEntityRankings {
  const AnalyticsEntityRankings({
    required this.period,
    required this.window,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.albumEditions,
  });

  final AnalyticsPeriod period;
  final AnalyticsTimeWindow window;

  final List<AnalyticsRankedEntity> songs;
  final List<AnalyticsRankedEntity> artists;
  final List<AnalyticsRankedEntity> albums;
  final List<AnalyticsRankedEntity> albumEditions;
}
