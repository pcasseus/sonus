// ignore_for_file: prefer_initializing_formals

import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../../domain/services/chart_ranking_engine.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../../domain/services/release_chart_eligibility.dart';
import 'chart_finalization_service.dart' show ChartRestoreGeneration;

typedef AllTimeMomentNow = DateTime Function();

/// Turns all-time chart achievements into Moments as soon as the play that
/// caused them is recorded, without waiting for a week to finish.
///
/// Every pass replays the full history, so the same achievement always has
/// the same key and saving it again changes nothing. Only plays from the
/// start of last chart week, and never before [activationUtc], are told as
/// stories: a first run or a restored backup does not flood the feed with
/// the past.
class AllTimeMomentService {
  AllTimeMomentService({
    required QualifiedPlayRepository qualifiedPlays,
    required LibraryQueryRepository library,
    required ChartMomentRepository moments,
    required DateTime activationUtc,
    AllTimeHistoryReplay replay = const AllTimeHistoryReplay(),
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    AllTimeMomentNow? now,
    ChartRestoreGeneration? restoreGeneration,
    ReleaseChartEligibility? releaseEligibility,
  }) : _qualifiedPlays = qualifiedPlays,
       _library = library,
       _moments = moments,
       _activationUtc = activationUtc.toUtc(),
       _replay = replay,
       _weeks = weekResolver,
       _now = now ?? DateTime.now,
       _restoreGeneration = restoreGeneration,
       _releaseEligibility = releaseEligibility;

  final QualifiedPlayRepository _qualifiedPlays;
  final LibraryQueryRepository _library;
  final ChartMomentRepository _moments;
  final DateTime _activationUtc;
  final AllTimeHistoryReplay _replay;
  final ChartWeekResolver _weeks;
  final AllTimeMomentNow _now;
  final ChartRestoreGeneration? _restoreGeneration;

  /// Singles never chart as releases, so they earn no release Moments.
  final ReleaseChartEligibility? _releaseEligibility;

  /// A debut below this rank is not news; reaching it later is.
  static const int debutStoryLimit = AllTimeHistoryReplay.hot100;

  /// Saves new achievements on both all-time charts and returns them.
  Future<List<ChartMomentEvent>> record({
    required DateTime referenceLocal,
  }) async {
    final generation = _restoreGeneration?.call();
    final plays = await _qualifiedPlays.getAll();
    final entities = await _entities();
    final singles = await excludedReleaseIds(_releaseEligibility);
    entities[ChartType.albums]!.removeWhere((id, _) => singles.contains(id));
    final from = _storiesFrom(referenceLocal);
    final createdAt = _now().toUtc();

    final events = <ChartMomentEvent>[
      for (final chartType in ChartType.values)
        ..._eventsFor(
          chartType,
          plays: chartType == ChartType.albums
              ? [
                  for (final play in plays)
                    if (!singles.contains(play.albumId)) play,
                ]
              : plays,
          entities: entities[chartType]!,
          referenceLocal: referenceLocal,
          from: from,
          createdAt: createdAt,
        ),
    ];

    if (events.isEmpty) return const [];

    if (_restoreGeneration?.call() != generation) {
      throw const LibraryMutationUnavailable(
        'The library was restored while chart Moments were being recorded.',
      );
    }
    await _moments.saveAll(events);
    return List.unmodifiable(events);
  }

  DateTime _storiesFrom(DateTime referenceLocal) {
    final thisWeek = _weeks.resolve(referenceLocal);
    final lastWeek = _weeks.resolve(
      thisWeek.startUtc.subtract(const Duration(hours: 1)).toLocal(),
    );
    final start = lastWeek.startUtc;
    return start.isAfter(_activationUtc) ? start : _activationUtc;
  }

  Iterable<ChartMomentEvent> _eventsFor(
    ChartType chartType, {
    required List<QualifiedPlay> plays,
    required Map<String, ChartEntitySnapshot> entities,
    required DateTime referenceLocal,
    required DateTime from,
    required DateTime createdAt,
  }) sync* {
    final result = _replay.run(
      events: [
        for (final play in plays)
          ChartRankingEvent(
            entityId: switch (chartType) {
              ChartType.songs => play.songId,
              ChartType.albums => play.albumId,
            },
            qualifiedAt: play.qualifiedAt,
            sourceEventId: play.id,
          ),
      ],
      referenceLocal: referenceLocal,
      achievementsFromUtc: from,
    );

    for (final achievement in result.achievements) {
      final entity = entities[achievement.entityId];
      if (entity == null) continue;
      if (achievement.type == AllTimeAchievementType.debut &&
          achievement.rank > debutStoryLimit) {
        continue;
      }
      yield _eventFor(chartType, achievement, entity, createdAt);
    }
  }

  ChartMomentEvent _eventFor(
    ChartType chartType,
    AllTimeAchievement achievement,
    ChartEntitySnapshot entity,
    DateTime createdAt,
  ) {
    final week = _weeks.resolve(achievement.occurredAt.toLocal());
    final key = achievement.deduplicationKey(chartType.name);
    final (type, threshold) = switch (achievement.type) {
      AllTimeAchievementType.debut => (ChartMomentEventType.debut, null),
      AllTimeAchievementType.top100Entry => (
        ChartMomentEventType.firstThresholdEntry,
        AllTimeHistoryReplay.hot100,
      ),
      AllTimeAchievementType.reentry => (ChartMomentEventType.reentry, null),
      AllTimeAchievementType.newPeak => (
        ChartMomentEventType.newPeak,
        achievement.zone,
      ),
      AllTimeAchievementType.numberOne => (
        ChartMomentEventType.firstNumberOne,
        1,
      ),
      AllTimeAchievementType.returnsToNumberOne => (
        ChartMomentEventType.returnToNumberOne,
        1,
      ),
      AllTimeAchievementType.bigClimb => (ChartMomentEventType.rankRise, null),
    };
    final previousPeak = achievement.previousPeakRank;

    return ChartMomentEvent(
      id: key,
      deduplicationKey: key,
      sourceId: achievement.playId,
      chartType: chartType,
      scope: ChartMomentScope.allTime,
      eventType: type,
      entity: entity,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      occurredAt: achievement.occurredAt.toUtc(),
      createdAt: createdAt,
      previousRank: achievement.previousRank,
      currentRank: achievement.rank,
      threshold: threshold,
      previousPeakRank: previousPeak,
      currentPeakRank: previousPeak == null || achievement.rank < previousPeak
          ? achievement.rank
          : previousPeak,
      qualifiedStreamCount: achievement.streams,
    );
  }

  Future<Map<ChartType, Map<String, ChartEntitySnapshot>>> _entities() async {
    final tracks = await _library.getTracks();
    final albums = await _library.getAlbums();
    return {
      ChartType.songs: {
        for (final track in tracks)
          if (!track.isBlocked)
            track.songId: ChartEntitySnapshot(
              entityId: track.songId,
              title: track.title,
              artistId: track.artistId,
              artistName: track.artistName,
              albumTitle: track.albumTitle,
            ),
      },
      ChartType.albums: {
        for (final album in albums)
          album.albumId: ChartEntitySnapshot(
            entityId: album.albumId,
            title: album.title,
            artistId: album.artistId,
            artistName: album.artistName,
          ),
      },
    };
  }
}
