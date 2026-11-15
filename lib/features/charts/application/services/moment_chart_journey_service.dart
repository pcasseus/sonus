// ignore_for_file: prefer_initializing_formals

import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/services/all_time_chart_ranking_engine.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../../domain/services/chart_ranking_engine.dart';
import '../../domain/services/release_chart_eligibility.dart';

typedef MomentJourneyNow = DateTime Function();

/// The songs the listener blocked, which the all-time chart leaves out of
/// its current ranks.
typedef BlockedSongIds = Future<Set<String>> Function();

/// A song's or release's verified journey on the all-time Sonus chart
/// (App Update 1.1), for a Moment's expanded story.
///
/// Every number comes from replaying the stored qualified plays exactly as
/// the all-time chart ranks them: ranks at completed day closes (local
/// midnight), the best rank ever reached, when it first charted and its
/// completed days. Nothing is smoothed, interpolated or estimated; a day it
/// finished outside the Top 200 is a gap.
class MomentChartJourney {
  const MomentChartJourney({
    required this.chartType,
    required this.entityId,
    required this.days,
    required this.totals,
    this.peakRank,
    this.firstChartedAt,
    this.currentRank,
  });

  final ChartType chartType;
  final String entityId;

  /// Every completed day since it first charted, oldest first.
  final List<ChartDayStanding> days;
  final ChartDayTotals totals;

  /// The best Top 200 rank it ever reached.
  final int? peakRank;
  final DateTime? firstChartedAt;

  /// Its rank now, after the latest play (null: outside the Top 200), as
  /// the all-time chart ranks it now: songs the listener blocked take no
  /// place (App Update 1.3, REF-1.3-02), so it matches the chart's row.
  /// Provisional and never stored.
  final int? currentRank;

  /// The last [count] completed days.
  List<ChartDayStanding> recent(int count) =>
      days.length <= count ? days : days.sublist(days.length - count);

  /// Whether there is anything to draw: two completed days with a rank.
  bool get hasJourney => days.where((day) => day.rank != null).length >= 2;
}

/// Loads [MomentChartJourney]s. Read-only: nothing is written.
class MomentChartJourneyService {
  MomentChartJourneyService({
    required QualifiedPlayRepository qualifiedPlays,
    ReleaseChartEligibility? releaseEligibility,
    AllTimeHistoryReplay replay = const AllTimeHistoryReplay(),
    AllTimeChartRankingEngine rankingEngine = const AllTimeChartRankingEngine(),
    BlockedSongIds? blockedSongIds,
    MomentJourneyNow? now,
  }) : _qualifiedPlays = qualifiedPlays,
       _releaseEligibility = releaseEligibility,
       _replay = replay,
       _rankingEngine = rankingEngine,
       _blockedSongIds = blockedSongIds,
       _now = now ?? DateTime.now;

  final QualifiedPlayRepository _qualifiedPlays;
  final ReleaseChartEligibility? _releaseEligibility;
  final AllTimeHistoryReplay _replay;
  final AllTimeChartRankingEngine _rankingEngine;
  final BlockedSongIds? _blockedSongIds;
  final MomentJourneyNow _now;

  Future<MomentChartJourney?> load({
    required ChartType chartType,
    required String entityId,
  }) async {
    final plays = await _qualifiedPlays.getAll();
    final singles = chartType == ChartType.albums
        ? await excludedReleaseIds(_releaseEligibility)
        : const <String>{};
    final events = [
      for (final QualifiedPlay play in plays)
        if (chartType == ChartType.songs || !singles.contains(play.albumId))
          ChartRankingEvent(
            entityId: chartType == ChartType.songs ? play.songId : play.albumId,
            qualifiedAt: play.qualifiedAt,
            sourceEventId: play.id,
          ),
    ];
    final now = _now();
    final result = _replay.run(
      events: events,
      referenceLocal: now,
      collectAchievements: false,
      collectDayStandings: {entityId},
    );
    if (!result.trackedRanks.containsKey(entityId)) return null;
    return MomentChartJourney(
      chartType: chartType,
      entityId: entityId,
      days: result.dayStandings[entityId] ?? const [],
      totals: result.daysOf(entityId),
      peakRank: result.trackedPeaks[entityId],
      firstChartedAt: result.trackedFirstCharted[entityId],
      currentRank: await _rankNow(
        chartType: chartType,
        entityId: entityId,
        events: events,
        now: now,
        replayed: result.trackedRanks[entityId],
      ),
    );
  }

  /// The rank now under the all-time chart's eligibility: on the song
  /// chart, blocked songs take no place and a blocked song has none (as
  /// AllTimeChartService ranks it). The completed days keep the replay's
  /// closes, as recorded.
  Future<int?> _rankNow({
    required ChartType chartType,
    required String entityId,
    required List<ChartRankingEvent> events,
    required DateTime now,
    required int? replayed,
  }) async {
    final blockedSongIds = _blockedSongIds;
    if (chartType != ChartType.songs || blockedSongIds == null) {
      return replayed;
    }
    final blocked = await blockedSongIds();
    if (blocked.isEmpty) return replayed;
    if (blocked.contains(entityId)) return null;
    final ranked = _rankingEngine.rank(
      events: events,
      comparisonStartUtc: now.toUtc(),
      eligibleEntityIds: {
        for (final event in events)
          if (!blocked.contains(event.entityId)) event.entityId,
      },
    );
    for (final entity in ranked) {
      if (entity.entityId != entityId) continue;
      return entity.rank <= ChartRankingEngine.extendedStandingsLimit
          ? entity.rank
          : null;
    }
    return null;
  }
}

/// How a page asks for a journey; provided by ChartsScope.
typedef MomentJourneyLoader =
    Future<MomentChartJourney?> Function(ChartType chartType, String entityId);
