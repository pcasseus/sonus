import '../analytics_behavior_metrics.dart';
import '../analytics_summary.dart';
import 'monthly_duration_change.dart';
import 'monthly_entity_listening_durations.dart';
import 'monthly_listening_distribution.dart';
import 'monthly_ranked_entity.dart';
import 'monthly_ranking_change.dart';

class MonthlyListeningInsights {
  const MonthlyListeningInsights({
    required this.selectedMonth,
    required this.previousMonth,
    required this.currentSummary,
    required this.previousSummary,
    required this.currentAudibleListeningDuration,
    required this.previousAudibleListeningDuration,
    required this.behavior,
    required this.distribution,
    required this.entityListeningDurations,
    required this.songs,
    required this.artists,
    required this.albums,
  });

  final DateTime selectedMonth;
  final DateTime previousMonth;

  final AnalyticsSummary currentSummary;
  final AnalyticsSummary previousSummary;

  final Duration currentAudibleListeningDuration;
  final Duration previousAudibleListeningDuration;

  final AnalyticsBehaviorMetrics behavior;
  final MonthlyListeningDistribution distribution;
  final MonthlyEntityListeningDurations entityListeningDurations;

  final List<MonthlyRankedEntity> songs;
  final List<MonthlyRankedEntity> artists;
  final List<MonthlyRankedEntity> albums;

  MonthlyRankingChange get streamChange => MonthlyRankingChange(
    currentValue: currentSummary.qualifiedStreamCount,
    previousValue: previousSummary.qualifiedStreamCount,
  );

  MonthlyDurationChange get listeningTimeChange => MonthlyDurationChange(
    current: currentAudibleListeningDuration,
    previous: previousAudibleListeningDuration,
  );

  MonthlyRankingChange get trackCountChange => MonthlyRankingChange(
    currentValue: currentSummary.distinctSongCount,
    previousValue: previousSummary.distinctSongCount,
  );

  MonthlyRankingChange get artistCountChange => MonthlyRankingChange(
    currentValue: currentSummary.distinctArtistCount,
    previousValue: previousSummary.distinctArtistCount,
  );

  MonthlyRankingChange get albumCountChange => MonthlyRankingChange(
    currentValue: currentSummary.distinctAlbumCount,
    previousValue: previousSummary.distinctAlbumCount,
  );

  bool get hasListening =>
      currentSummary.hasListening ||
      currentAudibleListeningDuration > Duration.zero;
}
