// ignore_for_file: prefer_initializing_formals

import '../../models/analytics_period.dart';
import '../../models/monthly_insights/monthly_listening_insights.dart';
import '../analytics_behavior_metrics_service.dart';
import '../analytics_entity_ranking_service.dart';
import '../analytics_listening_duration_service.dart';
import '../analytics_summary_service.dart';
import 'monthly_entity_listening_duration_service.dart';
import 'monthly_listening_distribution_service.dart';
import 'monthly_ranking_comparison_service.dart';

abstract interface class MonthlyListeningInsightsLoader {
  Future<MonthlyListeningInsights> load({required DateTime referenceLocal});
}

class MonthlyListeningInsightsService
    implements MonthlyListeningInsightsLoader {
  const MonthlyListeningInsightsService({
    required AnalyticsSummaryService summaries,
    required AnalyticsListeningDurationService listeningDurations,
    required AnalyticsBehaviorMetricsService behaviorMetrics,
    required AnalyticsEntityRankingService rankings,
    required MonthlyEntityListeningDurationService entityListeningDurations,
    required MonthlyListeningDistributionService distribution,
    MonthlyRankingComparisonService rankingComparison =
        const MonthlyRankingComparisonService(),
  }) : _summaries = summaries,
       _listeningDurations = listeningDurations,
       _behaviorMetrics = behaviorMetrics,
       _rankings = rankings,
       _entityListeningDurations = entityListeningDurations,
       _distribution = distribution,
       _rankingComparison = rankingComparison;

  final AnalyticsSummaryService _summaries;
  final AnalyticsListeningDurationService _listeningDurations;
  final AnalyticsBehaviorMetricsService _behaviorMetrics;
  final AnalyticsEntityRankingService _rankings;
  final MonthlyEntityListeningDurationService _entityListeningDurations;
  final MonthlyListeningDistributionService _distribution;
  final MonthlyRankingComparisonService _rankingComparison;

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async {
    final selectedMonth = DateTime(referenceLocal.year, referenceLocal.month);

    final previousMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);

    final currentSummaryFuture = _summaries.load(
      period: AnalyticsPeriod.month,
      referenceLocal: selectedMonth,
    );

    final previousSummaryFuture = _summaries.load(
      period: AnalyticsPeriod.month,
      referenceLocal: previousMonth,
    );

    final currentListeningFuture = _listeningDurations.load(
      period: AnalyticsPeriod.month,
      referenceLocal: selectedMonth,
    );

    final previousListeningFuture = _listeningDurations.load(
      period: AnalyticsPeriod.month,
      referenceLocal: previousMonth,
    );

    final behaviorFuture = _behaviorMetrics.load(
      period: AnalyticsPeriod.month,
      referenceLocal: selectedMonth,
    );

    final distributionFuture = _distribution.load(
      referenceLocal: selectedMonth,
    );

    final entityDurationsFuture = _entityListeningDurations.load(
      referenceLocal: selectedMonth,
    );

    final currentRankingsFuture = _rankings.load(
      period: AnalyticsPeriod.month,
      referenceLocal: selectedMonth,
    );

    final previousRankingsFuture = _rankings.load(
      period: AnalyticsPeriod.month,
      referenceLocal: previousMonth,
    );

    final lifetimeRankingsFuture = _rankings.load(
      period: AnalyticsPeriod.lifetime,
      referenceLocal: selectedMonth,
    );

    final currentSummary = await currentSummaryFuture;
    final previousSummary = await previousSummaryFuture;

    final currentListening = await currentListeningFuture;
    final previousListening = await previousListeningFuture;

    final behavior = await behaviorFuture;
    final distribution = await distributionFuture;
    final entityDurations = await entityDurationsFuture;

    final currentRankings = await currentRankingsFuture;
    final previousRankings = await previousRankingsFuture;
    final lifetimeRankings = await lifetimeRankingsFuture;

    return MonthlyListeningInsights(
      selectedMonth: selectedMonth,
      previousMonth: previousMonth,
      currentSummary: currentSummary,
      previousSummary: previousSummary,
      currentAudibleListeningDuration:
          currentListening.totalAudibleListeningDuration,
      previousAudibleListeningDuration:
          previousListening.totalAudibleListeningDuration,
      behavior: behavior,
      distribution: distribution,
      entityListeningDurations: entityDurations,
      songs: _rankingComparison.compare(
        current: currentRankings.songs,
        previous: previousRankings.songs,
        lifetime: lifetimeRankings.songs,
      ),
      artists: _rankingComparison.compare(
        current: currentRankings.artists,
        previous: previousRankings.artists,
        lifetime: lifetimeRankings.artists,
      ),
      albums: _rankingComparison.compare(
        current: currentRankings.albums,
        previous: previousRankings.albums,
        lifetime: lifetimeRankings.albums,
      ),
    );
  }
}
