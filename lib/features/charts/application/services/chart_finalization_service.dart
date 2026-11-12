// ignore_for_file: prefer_initializing_formals

import '../../../../core/database/library_mutation_coordinator.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_week.dart';
import '../../domain/moments/chart_moment_artist_achievement_detector.dart';
import '../../domain/moments/chart_history_evidence.dart';
import '../../domain/moments/chart_moment_artist_dominance.dart';
import '../../domain/moments/chart_moment_artist_joint_control.dart';
import '../../domain/moments/chart_moment_finalized_detector.dart';
import '../../domain/moments/chart_moment_lifetime_stream_service.dart';
import '../../domain/moments/chart_moment_longevity_calculator.dart';
import '../../domain/moments/chart_moment_milestone_detector.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/repositories/chart_repository.dart';
import '../../domain/repositories/chart_week_finalizer.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../../domain/services/release_chart_eligibility.dart';
import 'chart_snapshot_builder_service.dart';

typedef ChartFinalizationNow = DateTime Function();

/// Reads LibraryMutationCoordinator.restoreGeneration.
/// Entity id → the artist it counts for at artist level.
typedef ChartArtistAttribution = Future<Map<String, String>> Function();

typedef ChartRestoreGeneration = int Function();

/// The credits of each song, for joint chart control (REF-19).
typedef ChartSongCreditLookup =
    Future<Map<String, ChartSongCredits>> Function(Set<String> songIds);

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
    ChartMomentArtistDominanceDetector dominanceDetector =
        const ChartMomentArtistDominanceDetector(),
    Future<DateTime?> Function()? dominanceFromUtc,
    ChartMomentArtistJointControlDetector jointControlDetector =
        const ChartMomentArtistJointControlDetector(),
    Future<DateTime?> Function()? jointControlFromUtc,
    ChartSongCreditLookup? songCredits,
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
    ChartWeekFinalizer? weekFinalizer,
    Future<bool> Function(String chartType, DateTime weekStartUtc)?
    isRecalculatedWeek,
    Future<DateTime?> Function()? chartHistoryOriginUtc,
  }) : _builder = builder,
       _charts = charts,
       _qualifiedPlays = qualifiedPlays,
       _moments = moments,
       _finalizedMomentDetector = finalizedMomentDetector,
       _artistAchievementDetector = artistAchievementDetector,
       _dominanceDetector = dominanceDetector,
       _dominanceFromUtc = dominanceFromUtc,
       _jointControlDetector = jointControlDetector,
       _jointControlFromUtc = jointControlFromUtc,
       _songCredits = songCredits,
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
       _artistAttribution = artistAttribution,
       _weekFinalizer = weekFinalizer,
       _isRecalculatedWeek = isRecalculatedWeek,
       _chartHistoryOriginUtc = chartHistoryOriginUtc;

  /// When this database's chart history began (local version 46): its
  /// creation, upgrade or latest restore. Each week is finalized as
  /// [ChartSnapshotProvenance.original] only when it began at or after it
  /// and was not recalculated; otherwise as unverified. Without it, weeks
  /// are stored with their provenance unknown.
  final Future<DateTime?> Function()? _chartHistoryOriginUtc;

  /// App Update 1.2 (D5): a week recalculated after a permanent deletion
  /// publishes no new Moments; its surviving stories stay as they were.
  final Future<bool> Function(String chartType, DateTime weekStartUtc)?
  _isRecalculatedWeek;

  /// Writes a week's snapshot and Moments in one transaction (SN-50 F6).
  /// The app always provides it; without one (test doubles that cannot
  /// share a transaction) the earlier two-step write is used.
  final ChartWeekFinalizer? _weekFinalizer;

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
  final ChartMomentArtistDominanceDetector _dominanceDetector;

  /// Where artist-dominance Moments start on this install (REF-19): the
  /// first run of a build that carries them, recorded once. Only weeks
  /// still running then, or later, get them; a week that had already ended
  /// is never given them, even when it is finalized afterwards, so nothing
  /// is backfilled. Null (or unreadable): none this pass.
  final Future<DateTime?> Function()? _dominanceFromUtc;

  final ChartMomentArtistJointControlDetector _jointControlDetector;

  /// Where joint chart control Moments start (REF-19), like
  /// [_dominanceFromUtc] but their own: null until their lines are
  /// approved, so none are recorded before.
  final Future<DateTime?> Function()? _jointControlFromUtc;

  /// Without credits, joint control cannot be told from a collaboration,
  /// so none is recorded.
  final ChartSongCreditLookup? _songCredits;
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
      provenance: snapshot.provenance,
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

  /// A finalized week is frozen: once stored, it is returned as stored and
  /// never re-derived, whatever later plays, edits, blocks, restores or
  /// engine changes would now produce. Only a missing week is built.
  ///
  /// With [_weekFinalizer] the snapshot and its Moments are written in one
  /// transaction, which re-checks the week first: both are stored or
  /// neither is. Without it, the Moments are published before the
  /// snapshot, so a pass interrupted between the two writes finishes on
  /// the next pass without duplicating or replacing any published Moment.
  Future<ChartSnapshot> _reconcileType({
    required ChartType chartType,
    required ChartWeek week,
    required int? generation,
  }) async {
    final existing = await _charts.getForWeek(
      chartType: chartType,
      weekStartUtc: week.startUtc,
    );

    if (existing != null && existing.isFinalized) {
      return existing;
    }

    final built = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      finalizedAt: week.endUtc,
      revision: existing == null ? 1 : existing.revision + 1,
      excludedAlbumIds: chartType == ChartType.albums
          ? await excludedReleaseIds(_releaseEligibility)
          : const {},
    );
    final candidate = built.withProvenance(
      await _provenanceOf(chartType, week),
    );

    final events = await _detectFinalizedMoments(candidate);

    final finalizer = _weekFinalizer;
    if (finalizer != null) {
      // No await between this check and the transaction's admission.
      _ensureNoRestoreSince(generation);
      final stored = await finalizer.finalizeWeek(
        snapshot: candidate,
        moments: events,
      );
      return stored.snapshot;
    }

    if (events != null) {
      _ensureNoRestoreSince(generation);
      await _moments!.publishFinalizedForWeek(
        chartType: candidate.chartType,
        weekStartUtc: candidate.weekStartUtc,
        events: events,
      );
    }

    _ensureNoRestoreSince(generation);
    await _charts.replaceSnapshot(candidate);

    return candidate;
  }

  /// How [week] is being finalized now (REF-19). Unknown without a history
  /// origin reader; unverified when the origin is missing, the week began
  /// before it, or a deletion or merge recalculated the week.
  Future<ChartSnapshotProvenance?> _provenanceOf(
    ChartType chartType,
    ChartWeek week,
  ) async {
    final originReader = _chartHistoryOriginUtc;
    if (originReader == null) return null;
    final origin = await originReader();
    if (origin == null || week.startUtc.toUtc().isBefore(origin.toUtc())) {
      return ChartSnapshotProvenance.unverified;
    }
    final recalculated = _isRecalculatedWeek;
    if (recalculated != null &&
        await recalculated(chartType.name, week.startUtc.toUtc())) {
      return ChartSnapshotProvenance.unverified;
    }
    return ChartSnapshotProvenance.original;
  }

  /// The week's finalized Moments, or null when Moments are off or the
  /// week starts before they do. Reads only; nothing is written here.
  Future<List<ChartMomentEvent>?> _detectFinalizedMoments(
    ChartSnapshot snapshot,
  ) async {
    final moments = _moments;
    final activationWeekStartUtc = _momentsActivationWeekStartUtc;

    if (moments == null || activationWeekStartUtc == null) {
      return null;
    }

    final recalculated = _isRecalculatedWeek;
    if (recalculated != null &&
        await recalculated(
          snapshot.chartType.name,
          snapshot.weekStartUtc.toUtc(),
        )) {
      return null;
    }

    if (snapshot.weekStartUtc.toUtc().isBefore(activationWeekStartUtc)) {
      return null;
    }

    final history = await _charts.getHistory(snapshot.chartType);
    final createdAt = _now().toUtc();

    final events = _finalizedMomentDetector
        .detect(snapshot: snapshot, history: history, createdAt: createdAt)
        .toList();

    final artists = await _artistAttribution?.call() ?? const {};
    final attributed = _attributed(snapshot, artists);
    final attributedHistory = [
      for (final week in history) _attributed(week, artists),
    ];
    events.addAll(
      _artistAchievementDetector.detect(
        snapshot: attributed,
        history: attributedHistory,
        createdAt: createdAt,
      ),
    );
    if (await _dominanceApplies(snapshot)) {
      events.addAll(
        _dominanceDetector.detect(
          snapshot: attributed,
          history: attributedHistory,
          createdAt: createdAt,
          evidence: await _historyEvidence(snapshot, history),
        ),
      );
    }

    final songCredits = _songCredits;
    if (songCredits != null &&
        await _startsBefore(_jointControlFromUtc, snapshot)) {
      events.addAll(
        _jointControlDetector.detect(
          snapshot: attributed,
          history: attributedHistory,
          createdAt: createdAt,
          credits: await songCredits({
            for (final entry in snapshot.entries) entry.entity.entityId,
          }),
          chartArtists: {
            for (final entry in snapshot.entries)
              entry.entity.entityId: entry.entity.artistId,
          },
        ),
      );
    }

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

    return events;
  }

  /// What can be shown about the history behind [snapshot] (REF-19):
  /// nothing unless the week itself is original; otherwise the history's
  /// origin and every earlier week with plays but no finalized chart.
  Future<ChartHistoryEvidence> _historyEvidence(
    ChartSnapshot snapshot,
    List<ChartSnapshot> history,
  ) async {
    if (snapshot.provenance != ChartSnapshotProvenance.original) {
      return ChartHistoryEvidence.unverified;
    }
    final finalized = {
      for (final week in history)
        if (week.isFinalized && week.chartType == snapshot.chartType)
          week.weekStartUtc.toUtc(),
    };
    final incomplete = <DateTime>{};
    for (final play in await _qualifiedPlays.getAll(
      qualifiedBefore: snapshot.weekStartUtc,
    )) {
      final week = _weekResolver.resolve(play.qualifiedAt.toLocal());
      final start = week.startUtc.toUtc();
      if (start.isBefore(snapshot.weekStartUtc.toUtc()) &&
          !finalized.contains(start)) {
        incomplete.add(start);
      }
    }
    return ChartHistoryEvidence(
      currentWeekOriginal: true,
      historyOriginUtc: await _chartHistoryOriginUtc?.call(),
      incompleteWeekStartsUtc: incomplete,
    );
  }

  Future<bool> _dominanceApplies(ChartSnapshot snapshot) =>
      _startsBefore(_dominanceFromUtc, snapshot);

  /// Whether a start [from] exists and the songs [snapshot] was still
  /// running at it, or began after it: nothing is ever backfilled.
  static Future<bool> _startsBefore(
    Future<DateTime?> Function()? from,
    ChartSnapshot snapshot,
  ) async {
    final start = await from?.call();
    return start != null &&
        snapshot.chartType == ChartType.songs &&
        snapshot.weekEndUtc.toUtc().isAfter(start.toUtc());
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
}
