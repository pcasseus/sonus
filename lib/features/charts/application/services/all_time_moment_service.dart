// ignore_for_file: prefer_initializing_formals

import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../analytics/application/services/listening_artist_attribution.dart';
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
///
/// Facts recorded (SN-45), each only when it really happened:
/// - song and release achievements on the permanent Top 200, including
///   Bubbling Under debuts at their real position (#101–200), and for a #1
///   the entity it displaced;
/// - stream milestones of songs, releases and artists;
/// - an artist's first and later #1s, Top 10 and Top 100 entries, counted
///   for the artist each song belongs to (a soundtrack contributor's songs
///   count for the soundtrack's owner);
/// - an artist passing the previous most-streamed artist.
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
    ListeningArtistAttribution? artistAttribution,
  }) : _qualifiedPlays = qualifiedPlays,
       _library = library,
       _moments = moments,
       _activationUtc = activationUtc.toUtc(),
       _replay = replay,
       _weeks = weekResolver,
       _now = now ?? DateTime.now,
       _restoreGeneration = restoreGeneration,
       _releaseEligibility = releaseEligibility,
       _artistAttribution = artistAttribution;

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

  /// Which artist each play counts for; its stored artist without one.
  final ListeningArtistAttribution? _artistAttribution;

  /// Stream totals worth a story, sized for a personal library.
  static const List<int> songStreamMilestones = [
    25,
    50,
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
  ];
  static const List<int> releaseStreamMilestones = [
    50,
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
    25000,
  ];
  static const List<int> artistStreamMilestones = [
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
    25000,
  ];

  /// Saves new achievements on both all-time charts and the artist
  /// ranking, and returns them.
  Future<List<ChartMomentEvent>> record({
    required DateTime referenceLocal,
  }) async {
    final generation = _restoreGeneration?.call();
    final plays = await _qualifiedPlays.getAll();
    final attributor = await ArtistAttributor.of(_artistAttribution);
    final entities = await _entities(attributor);
    final singles = await excludedReleaseIds(_releaseEligibility);
    entities[ChartType.albums]!.removeWhere((id, _) => singles.contains(id));
    final from = _storiesFrom(referenceLocal);
    final createdAt = _now().toUtc();

    final events = <ChartMomentEvent>[
      ..._eventsFor(
        ChartType.songs,
        plays: plays,
        entities: entities[ChartType.songs]!,
        referenceLocal: referenceLocal,
        from: from,
        createdAt: createdAt,
      ),
      ..._eventsFor(
        ChartType.albums,
        plays: [
          for (final play in plays)
            if (!singles.contains(play.albumId)) play,
        ],
        entities: entities[ChartType.albums]!,
        referenceLocal: referenceLocal,
        from: from,
        createdAt: createdAt,
      ),
      ..._artistEvents(
        plays: plays,
        attributor: attributor,
        names: await _artistNames(),
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
      streamMilestones: switch (chartType) {
        ChartType.songs => songStreamMilestones,
        ChartType.albums => releaseStreamMilestones,
      },
      groupOf: (entityId) => entities[entityId]?.artistId,
    );

    for (final achievement in result.achievements) {
      final entity = entities[achievement.entityId];
      if (entity == null) continue;
      yield _eventFor(
        chartType,
        achievement,
        entity,
        createdAt,
        related: entities[achievement.displacedEntityId],
      );
    }
  }

  ChartMomentEvent _eventFor(
    ChartType chartType,
    AllTimeAchievement achievement,
    ChartEntitySnapshot entity,
    DateTime createdAt, {
    ChartEntitySnapshot? related,
  }) {
    final songs = chartType == ChartType.songs;
    final first = (achievement.milestone ?? 1) == 1;
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
      AllTimeAchievementType.streamMilestone => (
        ChartMomentEventType.lifetimeStreamMilestone,
        null,
      ),
      AllTimeAchievementType.careerNumberOne => (
        switch ((songs, first)) {
          (true, true) => ChartMomentEventType.artistFirstNumberOneSong,
          (true, false) => ChartMomentEventType.artistNthNumberOneSong,
          (false, true) => ChartMomentEventType.artistFirstNumberOneAlbum,
          (false, false) => ChartMomentEventType.artistNthNumberOneAlbum,
        },
        1,
      ),
      AllTimeAchievementType.careerTop10 ||
      AllTimeAchievementType.careerTop100 => (
        switch ((songs, first)) {
          (true, true) => ChartMomentEventType.artistFirstThresholdSong,
          (true, false) => ChartMomentEventType.artistNthThresholdSong,
          (false, true) => ChartMomentEventType.artistFirstThresholdAlbum,
          (false, false) => ChartMomentEventType.artistNthThresholdAlbum,
        },
        achievement.type == AllTimeAchievementType.careerTop10
            ? 10
            : AllTimeHistoryReplay.hot100,
      ),
    };
    final carriesMilestone = switch (achievement.type) {
      AllTimeAchievementType.streamMilestone ||
      AllTimeAchievementType.careerNumberOne ||
      AllTimeAchievementType.careerTop10 ||
      AllTimeAchievementType.careerTop100 => true,
      _ => false,
    };

    return _event(
      key: achievement.deduplicationKey(chartType.name),
      chartType: chartType,
      type: type,
      entity: entity,
      related: related,
      achievement: achievement,
      createdAt: createdAt,
      threshold: threshold,
      milestoneValue: carriesMilestone ? achievement.milestone : null,
    );
  }

  /// The artist ranking: every play counts once, for its attributed
  /// artist. An artist passing the previous leader, and artist stream
  /// milestones, are told; leading with no one to pass is not.
  Iterable<ChartMomentEvent> _artistEvents({
    required List<QualifiedPlay> plays,
    required ArtistAttributor attributor,
    required Map<String, String> names,
    required DateTime referenceLocal,
    required DateTime from,
    required DateTime createdAt,
  }) sync* {
    final result = _replay.run(
      events: [
        for (final play in plays)
          ChartRankingEvent(
            entityId: attributor.artistFor(
              artistId: play.artistId,
              albumId: play.albumId,
            ),
            qualifiedAt: play.qualifiedAt,
            sourceEventId: play.id,
          ),
      ],
      referenceLocal: referenceLocal,
      achievementsFromUtc: from,
      streamMilestones: artistStreamMilestones,
    );

    ChartEntitySnapshot? artist(String? id) {
      final name = id == null ? null : names[id];
      return id == null || name == null
          ? null
          : ChartEntitySnapshot(
              entityId: id,
              title: name,
              artistId: id,
              artistName: name,
            );
    }

    for (final achievement in result.achievements) {
      final entity = artist(achievement.entityId);
      if (entity == null) continue;

      switch (achievement.type) {
        case AllTimeAchievementType.numberOne ||
            AllTimeAchievementType.returnsToNumberOne:
          final passed = artist(achievement.displacedEntityId);
          if (passed == null) continue;
          yield _event(
            key:
                'alltime|artists|topArtist|${achievement.entityId}|'
                '${achievement.playId}',
            chartType: ChartType.songs,
            type: ChartMomentEventType.artistBecomesTopArtist,
            entity: entity,
            related: passed,
            achievement: achievement,
            createdAt: createdAt,
            threshold: 1,
          );
        case AllTimeAchievementType.streamMilestone:
          yield _event(
            key: achievement.deduplicationKey('artists'),
            chartType: ChartType.songs,
            type: ChartMomentEventType.artistStreamMilestone,
            entity: entity,
            achievement: achievement,
            createdAt: createdAt,
            milestoneValue: achievement.milestone,
          );
        default:
          continue;
      }
    }
  }

  ChartMomentEvent _event({
    required String key,
    required ChartType chartType,
    required ChartMomentEventType type,
    required ChartEntitySnapshot entity,
    required AllTimeAchievement achievement,
    required DateTime createdAt,
    ChartEntitySnapshot? related,
    int? threshold,
    int? milestoneValue,
  }) {
    final week = _weeks.resolve(achievement.occurredAt.toLocal());
    final rank = achievement.rank;
    final inStandings =
        rank >= 1 && rank <= ChartRankingEngine.extendedStandingsLimit;
    final previousPeak = achievement.previousPeakRank;

    return ChartMomentEvent(
      id: key,
      deduplicationKey: key,
      sourceId: achievement.playId,
      chartType: chartType,
      scope: ChartMomentScope.allTime,
      eventType: type,
      entity: entity,
      relatedEntity: related,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      occurredAt: achievement.occurredAt.toUtc(),
      createdAt: createdAt,
      previousRank: achievement.previousRank,
      currentRank: inStandings ? rank : null,
      threshold: threshold,
      previousPeakRank: previousPeak,
      currentPeakRank: !inStandings
          ? previousPeak
          : previousPeak == null || rank < previousPeak
          ? rank
          : previousPeak,
      qualifiedStreamCount: achievement.streams,
      milestoneValue: milestoneValue,
    );
  }

  /// Songs (not blocked) and releases by id. A song's artist is the
  /// artist its plays count for; its credit stays as tagged.
  Future<Map<ChartType, Map<String, ChartEntitySnapshot>>> _entities(
    ArtistAttributor attributor,
  ) async {
    final tracks = await _library.getTracks();
    final albums = await _library.getAlbums();
    return {
      ChartType.songs: {
        for (final track in tracks)
          if (!track.isBlocked)
            track.songId: ChartEntitySnapshot(
              entityId: track.songId,
              title: track.title,
              artistId: attributor.artistFor(
                artistId: track.artistId,
                albumId: track.albumId,
              ),
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

  Future<Map<String, String>> _artistNames() async => {
    for (final artist in await _library.getArtists())
      artist.artistId: artist.name,
  };
}
