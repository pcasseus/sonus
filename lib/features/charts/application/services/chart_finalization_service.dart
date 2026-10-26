// ignore_for_file: prefer_initializing_formals

import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_week.dart';
import '../../domain/moments/chart_moment_artist_achievement_detector.dart';
import '../../domain/moments/chart_moment_finalized_detector.dart';
import '../../domain/moments/chart_moment_lifetime_stream_service.dart';
import '../../domain/moments/chart_moment_longevity_calculator.dart';
import '../../domain/moments/chart_moment_milestone_detector.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/repositories/chart_repository.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../../domain/services/release_chart_eligibility.dart';
import 'chart_snapshot_builder_service.dart';

typedef ChartFinalizationNow = DateTime Function();

/// Reads LibraryMutationCoordinator.restoreGeneration.
/// Entity id → the artist it counts for at artist level.
typedef ChartArtistAttribution = Future<Map<String, String>> Function();

typedef ChartRestoreGeneration = int Function();

class ChartFinalizationService {
  ChartFinalizationService({
    required ChartSnapshotBuilderService builder,
    required ChartRepository charts,
    required QualifiedPlayRepository qualifiedPlays,
    ChartMomentRepository? moments,
    ChartMomentFinalizedDetector finalizedMomentDetector =
        const ChartMomentFinalizedDetector(),
    ChartMomentArtistAchievementDetector artistAchievementDetector =
        const ChartMomentArtistAchievementDetector(),
    ChartMomentLongevityCalculator longevityCalculator =
        const ChartMomentLongevityCalculator(),
    ChartMomentMilestoneDetector milestoneDetector =
        const ChartMomentMilestoneDetector(),
    ChartMomentLifetimeStreamService? lifetimeStreamService,
    DateTime? momentsActivationWeekStartUtc,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    ChartFinalizationNow? now,
    ChartRestoreGeneration? restoreGeneration,
    ReleaseChartEligibility? releaseEligibility,
    ChartArtistAttribution? artistAttribution,
  }) : _builder = builder,
       _charts = charts,
       _qualifiedPlays = qualifiedPlays,
       _moments = moments,
       _finalizedMomentDetector = finalizedMomentDetector,
       _artistAchievementDetector = artistAchievementDetector,
       _longevityCalculator = longevityCalculator,
       _milestoneDetector = milestoneDetector,
       _lifetimeStreamService =
           lifetimeStreamService ??
           ChartMomentLifetimeStreamService(qualifiedPlays: qualifiedPlays),
       _momentsActivationWeekStartUtc = momentsActivationWeekStartUtc?.toUtc(),
       _weekResolver = weekResolver,
       _now = now ?? DateTime.now,
       _restoreGeneration = restoreGeneration,
       _releaseEligibility = releaseEligibility,
       _artistAttribution = artistAttribution;

  final ChartSnapshotBuilderService _builder;

  /// Singles never chart as releases. A finalized week is never rewritten
  /// for it: a Single already on a stored week stays there.
  final ReleaseChartEligibility? _releaseEligibility;

  /// The artist each charting song or release counts for, by entity id.
  /// Weekly artist achievements group by it, so a soundtrack contributor's
  /// songs count for the soundtrack's owner, never for an artist-chart
  /// identity of their own. Stored charts keep their recorded artists.
  final ChartArtistAttribution? _artistAttribution;
  final ChartRepository _charts;
  final QualifiedPlayRepository _qualifiedPlays;

  final ChartMomentRepository? _moments;
  final ChartMomentFinalizedDetector _finalizedMomentDetector;
  final ChartMomentArtistAchievementDetector _artistAchievementDetector;
  final ChartMomentLongevityCalculator _longevityCalculator;
  final ChartMomentMilestoneDetector _milestoneDetector;
  final ChartMomentLifetimeStreamService _lifetimeStreamService;
  final DateTime? _momentsActivationWeekStartUtc;

  final ChartWeekResolver _weekResolver;
  final ChartFinalizationNow _now;
  final ChartRestoreGeneration? _restoreGeneration;

  /// [snapshot] with each entry's artist replaced by the artist it counts
  /// for, for artist-level detection only.
  static ChartSnapshot _attributed(
    ChartSnapshot snapshot,
    Map<String, String> artists,
  ) {
    if (artists.isEmpty) return snapshot;
    return ChartSnapshot(
      id: snapshot.id,
      chartType: snapshot.chartType,
      weekStartUtc: snapshot.weekStartUtc,
      weekEndUtc: snapshot.weekEndUtc,
      finalizedAt: snapshot.finalizedAt,
      revision: snapshot.revision,
      entries: [
        for (final entry in snapshot.entries)
          ChartEntry(
            entity: ChartEntitySnapshot(
              entityId: entry.entity.entityId,
              title: entry.entity.title,
              artistName: entry.entity.artistName,
              artistId: artists[entry.entity.entityId] ?? entry.entity.artistId,
              albumTitle: entry.entity.albumTitle,
            ),
            rank: entry.rank,
            qualifiedStreamCount: entry.qualifiedStreamCount,
            lastQualifiedAt: entry.lastQualifiedAt,
            previousFinalRank: entry.previousFinalRank,
            peakRank: entry.peakRank,
            peakAchievedAt: entry.peakAchievedAt,
            weeksOnChart: entry.weeksOnChart,
            movement: entry.movement,
          ),
      ],
    );
  }

  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async {
    // Captured once, before any read: the whole pass, including its list of
    // weeks, is computed from the library as it was at this point.
    final generation = _restoreGeneration?.call();
    final currentWeek = _weekResolver.resolve(referenceLocal);

    final plays = await _qualifiedPlays.getAll(
      qualifiedBefore: currentWeek.startUtc,
    );

    final weeksByStartUtc = <String, ChartWeek>{};

    for (final play in plays) {
      final week = _weekResolver.resolve(play.qualifiedAt.toLocal());

      if (!week.startUtc.isBefore(currentWeek.startUtc)) {
        continue;
      }

      weeksByStartUtc[week.startUtc.toIso8601String()] = week;
    }

    final weeks = weeksByStartUtc.values.toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));

    final results = <ChartSnapshot>[];

    for (final week in weeks) {
      results.addAll(await _reconcileWeek(week, generation));
    }

    return List<ChartSnapshot>.unmodifiable(results);
  }

  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) {
    final previousWeekReference = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day - 7,
      12,
    );

    final week = _weekResolver.resolve(previousWeekReference);

    return reconcileCompletedWeek(week);
  }

  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) {
    return _reconcileWeek(week, _restoreGeneration?.call());
  }

  Future<List<ChartSnapshot>> _reconcileWeek(
    ChartWeek week,
    int? generation,
  ) async {
    final results = <ChartSnapshot>[];

    for (final chartType in ChartType.values) {
      results.add(
        await _reconcileType(
          chartType: chartType,
          week: week,
          generation: generation,
        ),
      );
    }

    return List<ChartSnapshot>.unmodifiable(results);
  }

  /// A restore since [captured] may have replaced what this pass read, so
  /// its results must not be written into the restored library. Called
  /// immediately before each write, with no await before the write's own
  /// admission check, so no restore can be requested in between.
  void _ensureNoRestoreSince(int? captured) {
    final current = _restoreGeneration?.call();

    if (current != captured) {
      throw const LibraryMutationUnavailable(
        'The library was restored while charts were being finalized.',
      );
    }
  }

  Future<ChartSnapshot> _reconcileType({
    required ChartType chartType,
    required ChartWeek week,
    required int? generation,
  }) async {
    final existing = await _charts.getForWeek(
      chartType: chartType,
      weekStartUtc: week.startUtc,
    );

    final candidate = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      finalizedAt: week.endUtc,
      revision: existing == null ? 1 : existing.revision + 1,
      excludedAlbumIds: chartType == ChartType.albums
          ? {
              for (final id in await excludedReleaseIds(_releaseEligibility))
                if (existing == null ||
                    !existing.entries.any((e) => e.entity.entityId == id))
                  id,
            }
          : const {},
    );

    late final ChartSnapshot canonical;

    if (existing != null && _sameChartContent(existing, candidate)) {
      canonical = existing;
    } else {
      _ensureNoRestoreSince(generation);
      await _charts.replaceSnapshot(candidate);
      canonical = candidate;
    }

    await _reconcileFinalizedMoments(canonical, generation);

    return canonical;
  }

  Future<void> _reconcileFinalizedMoments(
    ChartSnapshot snapshot,
    int? generation,
  ) async {
    final moments = _moments;
    final activationWeekStartUtc = _momentsActivationWeekStartUtc;

    if (moments == null || activationWeekStartUtc == null) {
      return;
    }

    if (snapshot.weekStartUtc.toUtc().isBefore(activationWeekStartUtc)) {
      return;
    }

    final history = await _charts.getHistory(snapshot.chartType);
    final createdAt = _now().toUtc();

    final events = _finalizedMomentDetector
        .detect(snapshot: snapshot, history: history, createdAt: createdAt)
        .toList();

    final artists = await _artistAttribution?.call() ?? const {};
    events.addAll(
      _artistAchievementDetector.detect(
        snapshot: _attributed(snapshot, artists),
        history: [for (final week in history) _attributed(week, artists)],
        createdAt: createdAt,
      ),
    );

    final previousSnapshot =
        _immediatePreviousSnapshot(snapshot: snapshot, history: history) ??
        _emptyPreviousWeek(snapshot);

    final previousLifetimeStreams = await _lifetimeStreamService.loadBefore(
      chartType: snapshot.chartType,
      qualifiedBeforeUtc: snapshot.weekStartUtc,
    );

    final currentLifetimeStreams = await _lifetimeStreamService.load(
      snapshot: snapshot,
    );

    for (final entry in snapshot.entries) {
      final entityId = entry.entity.entityId;

      final previousLongevity = _longevityCalculator.calculate(
        entityId: entityId,
        snapshot: previousSnapshot,
        history: history,
      );

      final currentLongevity = _longevityCalculator.calculate(
        entityId: entityId,
        snapshot: snapshot,
        history: history,
      );

      events.addAll(
        _milestoneDetector.detect(
          snapshot: snapshot,
          entry: entry,
          previousLongevity: previousLongevity,
          currentLongevity: currentLongevity,
          previousLifetimeStreams: previousLifetimeStreams[entityId] ?? 0,
          currentLifetimeStreams: currentLifetimeStreams[entityId] ?? 0,
          createdAt: createdAt,
        ),
      );
    }

    _ensureNoRestoreSince(generation);
    await moments.replaceFinalizedForWeek(
      chartType: snapshot.chartType,
      weekStartUtc: snapshot.weekStartUtc,
      events: events,
    );
  }

  static ChartSnapshot? _immediatePreviousSnapshot({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
  }) {
    final matching = history
        .where(
          (historical) =>
              historical.isFinalized &&
              historical.chartType == snapshot.chartType &&
              historical.weekEndUtc.toUtc() == snapshot.weekStartUtc.toUtc(),
        )
        .toList(growable: false);

    if (matching.length > 1) {
      throw StateError(
        'Multiple finalized snapshots end at '
        '${snapshot.weekStartUtc.toUtc().toIso8601String()} '
        'for ${snapshot.chartType.name}.',
      );
    }

    return matching.isEmpty ? null : matching.single;
  }

  static ChartSnapshot _emptyPreviousWeek(ChartSnapshot snapshot) {
    final weekEndUtc = snapshot.weekStartUtc.toUtc();
    final weekStartUtc = weekEndUtc.subtract(const Duration(days: 7));

    return ChartSnapshot(
      id:
          'moment-baseline:${snapshot.chartType.name}:'
          '${weekStartUtc.millisecondsSinceEpoch}',
      chartType: snapshot.chartType,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: weekEndUtc,
      entries: const [],
    );
  }

  static bool _sameChartContent(
    ChartSnapshot existing,
    ChartSnapshot candidate,
  ) {
    if (existing.id != candidate.id ||
        existing.chartType != candidate.chartType ||
        existing.weekStartUtc.toUtc() != candidate.weekStartUtc.toUtc() ||
        existing.weekEndUtc.toUtc() != candidate.weekEndUtc.toUtc() ||
        existing.entries.length != candidate.entries.length) {
      return false;
    }

    for (var index = 0; index < existing.entries.length; index++) {
      if (!_sameEntry(existing.entries[index], candidate.entries[index])) {
        return false;
      }
    }

    return true;
  }

  static bool _sameEntry(ChartEntry existing, ChartEntry candidate) {
    return existing.entity.entityId == candidate.entity.entityId &&
        existing.entity.title == candidate.entity.title &&
        existing.entity.artistId == candidate.entity.artistId &&
        existing.entity.artistName == candidate.entity.artistName &&
        existing.entity.albumTitle == candidate.entity.albumTitle &&
        existing.rank == candidate.rank &&
        existing.qualifiedStreamCount == candidate.qualifiedStreamCount &&
        existing.lastQualifiedAt.toUtc() == candidate.lastQualifiedAt.toUtc() &&
        existing.previousFinalRank == candidate.previousFinalRank &&
        existing.peakRank == candidate.peakRank &&
        existing.peakAchievedAt.toUtc() == candidate.peakAchievedAt.toUtc() &&
        existing.weeksOnChart == candidate.weeksOnChart &&
        existing.movement == candidate.movement;
  }
}
