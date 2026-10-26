// ignore_for_file: prefer_initializing_formals

import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../domain/entities/all_time_chart.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/all_time_entry_stats.dart';
import '../../domain/models/all_time_ranked_entity.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../../domain/services/all_time_chart_ranking_engine.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../../domain/services/chart_ranking_engine.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../../domain/services/release_chart_eligibility.dart';

/// Builds the permanent all-time chart from every qualified play.
///
/// A play counts toward the song it played and the album it belonged to when
/// it qualified, so a song shared by Standard and Deluxe editions adds one
/// play to one album. This matches the lifetime totals Chart Moments use.
class AllTimeChartService {
  const AllTimeChartService({
    required QualifiedPlayRepository qualifiedPlays,
    required LibraryQueryRepository library,
    AllTimeChartRankingEngine rankingEngine = const AllTimeChartRankingEngine(),
    AllTimeHistoryReplay replay = const AllTimeHistoryReplay(),
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    ReleaseChartEligibility? releaseEligibility,
  }) : _qualifiedPlays = qualifiedPlays,
       _library = library,
       _rankingEngine = rankingEngine,
       _replay = replay,
       _weekResolver = weekResolver,
       _releaseEligibility = releaseEligibility;

  final QualifiedPlayRepository _qualifiedPlays;
  final LibraryQueryRepository _library;
  final AllTimeChartRankingEngine _rankingEngine;
  final AllTimeHistoryReplay _replay;
  final ChartWeekResolver _weekResolver;

  /// Singles never chart as releases; without this every album does.
  final ReleaseChartEligibility? _releaseEligibility;

  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async {
    final comparisonStartUtc = _weekResolver.resolve(referenceLocal).startUtc;
    final excluded = chartType == ChartType.albums
        ? await excludedReleaseIds(_releaseEligibility)
        : const <String>{};
    final plays = await _qualifiedPlays.getAll();
    final entities = await _currentEntities(chartType)
      ..removeWhere((id, _) => excluded.contains(id));

    // A Single's plays never enter the release chart, so it neither takes
    // a place nor pushes other releases down.
    final events = [
      for (final play in plays)
        if (!excluded.contains(_entityIdFor(play, chartType)))
          ChartRankingEvent(
            entityId: _entityIdFor(play, chartType),
            qualifiedAt: play.qualifiedAt,
            sourceEventId: play.id,
          ),
    ];
    final ranked = _rankingEngine.rank(
      events: events,
      comparisonStartUtc: comparisonStartUtc,
      eligibleEntityIds: entities.keys.toSet(),
    );
    final shown = ranked.take(viewSize.limit).toList(growable: false);

    return AllTimeChart(
      chartType: chartType,
      comparisonStartUtc: comparisonStartUtc,
      entries: List<ChartEntry>.unmodifiable([
        for (final result in shown)
          _entryFor(result, entities[result.entityId]!),
      ]),
      stats: _statsFor(
        shown.map((result) => result.entityId).toSet(),
        events: events,
        referenceLocal: referenceLocal,
        weekStartUtc: comparisonStartUtc,
      ),
    );
  }

  Map<String, AllTimeEntryStats> _statsFor(
    Set<String> entityIds, {
    required List<ChartRankingEvent> events,
    required DateTime referenceLocal,
    required DateTime weekStartUtc,
  }) {
    final now = referenceLocal.toUtc();
    final lastWeekStart = _weekResolver
        .resolve(weekStartUtc.subtract(const Duration(hours: 1)).toLocal())
        .startUtc;
    final lastWeekCutoff = lastWeekStart.add(now.difference(weekStartUtc));

    final thisWeek = <String, int>{};
    final lastWeek = <String, int>{};
    for (final event in events) {
      if (!entityIds.contains(event.entityId)) continue;
      final at = event.qualifiedAt.toUtc();
      if (!at.isBefore(weekStartUtc) && !at.isAfter(now)) {
        thisWeek[event.entityId] = (thisWeek[event.entityId] ?? 0) + 1;
      } else if (!at.isBefore(lastWeekStart) && at.isBefore(lastWeekCutoff)) {
        lastWeek[event.entityId] = (lastWeek[event.entityId] ?? 0) + 1;
      }
    }

    final replayed = _replay.run(
      events: events,
      referenceLocal: referenceLocal,
      collectAchievements: false,
    );

    return Map.unmodifiable({
      for (final id in entityIds)
        id: AllTimeEntryStats(
          streamsThisWeek: thisWeek[id] ?? 0,
          streamsSameTimeLastWeek: lastWeek[id] ?? 0,
          zones: replayed.zonesOf(id),
        ),
    });
  }

  /// Songs that are in the library and not blocked, or albums in the
  /// library, keyed by id.
  Future<Map<String, ChartEntitySnapshot>> _currentEntities(
    ChartType chartType,
  ) async {
    switch (chartType) {
      case ChartType.songs:
        final tracks = await _library.getTracks();
        return {
          for (final track in tracks)
            if (!track.isBlocked)
              track.songId: ChartEntitySnapshot(
                entityId: track.songId,
                title: track.title,
                artistId: track.artistId,
                artistName: track.artistName,
                albumTitle: track.albumTitle,
              ),
        };

      case ChartType.albums:
        final albums = await _library.getAlbums();
        return {
          for (final album in albums)
            album.albumId: ChartEntitySnapshot(
              entityId: album.albumId,
              title: album.title,
              artistId: album.artistId,
              artistName: album.artistName,
            ),
        };
    }
  }

  static String _entityIdFor(QualifiedPlay play, ChartType chartType) =>
      switch (chartType) {
        ChartType.songs => play.songId,
        ChartType.albums => play.albumId,
      };

  static ChartEntry _entryFor(
    AllTimeRankedEntity result,
    ChartEntitySnapshot entity,
  ) {
    return ChartEntry(
      entity: entity,
      rank: result.rank,
      qualifiedStreamCount: result.lifetimeStreamCount,
      lastQualifiedAt: result.lastQualifiedAt,
      previousFinalRank: result.previousRank,
      peakRank: result.peakRank,
      peakAchievedAt: result.peakAchievedAt,
      weeksOnChart: 0,
      movement: result.movement,
    );
  }
}
