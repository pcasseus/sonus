import '../models/chart_movement.dart';
import '../models/chart_ranked_entity.dart';
import '../models/chart_ranking_history.dart';
import '../moments/chart_moment_rank_observation.dart';

class ChartRankingEvent {
  const ChartRankingEvent({
    required this.entityId,
    required this.qualifiedAt,
    this.sourceEventId,
  });

  final String entityId;
  final DateTime qualifiedAt;

  /// Stable id of the qualified listening event responsible for this
  /// standings recalculation.
  ///
  /// Pure ranking callers may omit this when Moment observation is unused.
  final String? sourceEventId;
}

typedef ChartRankObservationCallback =
    void Function(ChartMomentRankObservation observation);

class ChartRankingEngine {
  const ChartRankingEngine();

  static const int officialChartLimit = 100;
  static const int extendedStandingsLimit = 200;

  List<ChartRankedEntity> rank({
    required Iterable<ChartRankingEvent> events,
    Map<String, ChartRankingHistory> historyByEntityId = const {},
    Set<String>? eligibleEntityIds,
    ChartRankObservationCallback? onRankObservation,
    bool includeObservedPeakInResult = true,
  }) {
    final orderedEvents = events.toList(growable: false)..sort(_compareEvents);

    final states = <String, _MutableChartState>{};

    for (final event in orderedEvents) {
      if (eligibleEntityIds != null &&
          !eligibleEntityIds.contains(event.entityId)) {
        continue;
      }

      final state = states.putIfAbsent(
        event.entityId,
        () => _MutableChartState(
          entityId: event.entityId,
          history: historyByEntityId[event.entityId],
        ),
      );

      state.qualifiedStreamCount++;
      state.lastQualifiedAt = event.qualifiedAt.toUtc();

      final standings = states.values.toList(growable: false)
        ..sort(_compareStates);

      for (var index = 0; index < standings.length; index++) {
        final rankedState = standings[index];
        final rank = index + 1;
        final hadPreviousObservation = rankedState.hasRankObservation;
        final previousRank = rankedState.lastObservedChartRank;
        final currentRank = rank <= extendedStandingsLimit ? rank : null;

        final previousPeakRank = _momentPeakRank(
          historicalPeakRank: rankedState.history?.peakRank,
          livePeakRank: rankedState.livePeakRank,
        );
        final chartedEarlierThisWeek = rankedState.firstChartedAt != null;

        rankedState.observeRank(
          rank: rank,
          observedAt: event.qualifiedAt.toUtc(),
        );

        final currentPeakRank = _momentPeakRank(
          historicalPeakRank: rankedState.history?.peakRank,
          livePeakRank: rankedState.livePeakRank,
        );

        final sourceEventId = event.sourceEventId;

        if (sourceEventId != null && onRankObservation != null) {
          onRankObservation(
            ChartMomentRankObservation(
              sourceEventId: sourceEventId,
              entityId: rankedState.entityId,
              hadPreviousObservation: hadPreviousObservation,
              previousRank: previousRank,
              currentRank: currentRank,
              previousPeakRank: previousPeakRank,
              currentPeakRank: currentPeakRank,
              previousFinalizedRank: rankedState.history?.previousExtendedRank,
              chartedEarlierThisWeek: chartedEarlierThisWeek,
              observedAt: event.qualifiedAt.toUtc(),
            ),
          );
        }
      }
    }

    final standings = states.values.toList(growable: false)
      ..sort(_compareStates);

    final results = <ChartRankedEntity>[];

    for (
      var index = 0;
      index < standings.length && index < extendedStandingsLimit;
      index++
    ) {
      final state = standings[index];
      final rank = index + 1;
      final history = state.history;

      final priorPeakRank = history?.peakRank;
      final priorPeakAchievedAt = history?.peakAchievedAt;

      final resultPeakRank = includeObservedPeakInResult
          ? state.livePeakRank
          : null;
      final resultPeakAchievedAt = includeObservedPeakInResult
          ? state.livePeakAchievedAt
          : null;

      final resolvedPeakRank = _resolvedPeakRank(
        priorPeakRank: priorPeakRank,
        livePeakRank: resultPeakRank,
        currentRank: rank,
      );

      final resolvedPeakAchievedAt = _resolvedPeakAchievedAt(
        resolvedPeakRank: resolvedPeakRank,
        priorPeakRank: priorPeakRank,
        priorPeakAchievedAt: priorPeakAchievedAt,
        livePeakRank: resultPeakRank,
        livePeakAchievedAt: resultPeakAchievedAt,
        fallbackAt: state.lastQualifiedAt!,
      );

      final previousFinalRank = history?.previousFinalRank;

      results.add(
        ChartRankedEntity(
          entityId: state.entityId,
          rank: rank,
          qualifiedStreamCount: state.qualifiedStreamCount,
          lastQualifiedAt: state.lastQualifiedAt!,
          previousFinalRank: previousFinalRank,
          peakRank: resolvedPeakRank,
          peakAchievedAt: resolvedPeakAchievedAt,
          weeksOnChart: history?.finalizedWeeksOnChart ?? 0,
          movement: _movementFor(
            state: state,
            currentRank: rank,
            history: history,
          ),
          hasEnteredOfficialChartThisWeek:
              state.hasEnteredOfficialChartThisWeek,
          hasReenteredOfficialChartThisWeek:
              state.hasReenteredOfficialChartThisWeek,
          previousExtendedRank: history?.previousExtendedRank,
          priorPeakRank: priorPeakRank,
          firstChartedAt: state.firstChartedAt,
          firstHot100At: state.firstHot100At,
        ),
      );
    }

    return List<ChartRankedEntity>.unmodifiable(results);
  }

  static int _compareEvents(ChartRankingEvent a, ChartRankingEvent b) {
    final timeComparison = a.qualifiedAt.toUtc().compareTo(
      b.qualifiedAt.toUtc(),
    );

    if (timeComparison != 0) {
      return timeComparison;
    }

    return a.entityId.compareTo(b.entityId);
  }

  static int _compareStates(_MutableChartState a, _MutableChartState b) {
    final streamComparison = b.qualifiedStreamCount.compareTo(
      a.qualifiedStreamCount,
    );

    if (streamComparison != 0) {
      return streamComparison;
    }

    final aLast = a.lastQualifiedAt;
    final bLast = b.lastQualifiedAt;

    if (aLast != null && bLast != null) {
      final recentComparison = bLast.compareTo(aLast);

      if (recentComparison != 0) {
        return recentComparison;
      }
    }

    return a.entityId.compareTo(b.entityId);
  }

  static int? _momentPeakRank({
    required int? historicalPeakRank,
    required int? livePeakRank,
  }) {
    int? peak;

    if (historicalPeakRank != null &&
        historicalPeakRank <= extendedStandingsLimit) {
      peak = historicalPeakRank;
    }

    if (livePeakRank != null && livePeakRank <= extendedStandingsLimit) {
      if (peak == null || livePeakRank < peak) {
        peak = livePeakRank;
      }
    }

    return peak;
  }

  static int _resolvedPeakRank({
    required int? priorPeakRank,
    required int? livePeakRank,
    required int currentRank,
  }) {
    var peak = currentRank;

    if (livePeakRank != null && livePeakRank < peak) {
      peak = livePeakRank;
    }

    if (priorPeakRank != null && priorPeakRank < peak) {
      peak = priorPeakRank;
    }

    return peak;
  }

  static DateTime _resolvedPeakAchievedAt({
    required int resolvedPeakRank,
    required int? priorPeakRank,
    required DateTime? priorPeakAchievedAt,
    required int? livePeakRank,
    required DateTime? livePeakAchievedAt,
    required DateTime fallbackAt,
  }) {
    if (priorPeakRank == resolvedPeakRank && priorPeakAchievedAt != null) {
      return priorPeakAchievedAt.toUtc();
    }

    if (livePeakRank == resolvedPeakRank && livePeakAchievedAt != null) {
      return livePeakAchievedAt.toUtc();
    }

    return fallbackAt.toUtc();
  }

  /// Last week's final official rank always decides the arrow; a dip out of
  /// the Top 100 during the week never overrides it (SN-50 E-Q2).
  ///
  /// RE-ENTRY comes only from finalized chart history (user decision
  /// 2026-11-16): leaving and returning within the provisional live week is
  /// never a re-entry, so an entity with no finalized history stays NEW
  /// however often it crosses the Top 100 line that week.
  /// [ChartRankedEntity.hasReenteredOfficialChartThisWeek] remains a
  /// recorded fact and does not decide movement.
  static ChartMovement _movementFor({
    required _MutableChartState state,
    required int currentRank,
    required ChartRankingHistory? history,
  }) {
    final previousFinalRank = history?.previousFinalRank;

    if (previousFinalRank != null) {
      if (currentRank < previousFinalRank) {
        return ChartMovement.up;
      }

      if (currentRank > previousFinalRank) {
        return ChartMovement.down;
      }

      return ChartMovement.same;
    }

    if (history?.hasEverCharted == true) {
      return ChartMovement.reentry;
    }

    // Bubbling Under is its own chart: back in #101–200 after a week away
    // from the Top 200 is a RE-ENTRY there, never NEW, when an earlier
    // finalized week had it in the Top 200 (App Update 1.3 movement rules;
    // history peaks come only from persisted Top 200 rows).
    if (currentRank > officialChartLimit &&
        history?.previousExtendedRank == null &&
        history?.peakRank != null) {
      return ChartMovement.reentry;
    }

    return ChartMovement.newEntry;
  }
}

class _MutableChartState {
  _MutableChartState({required this.entityId, required this.history});

  final String entityId;
  final ChartRankingHistory? history;

  int qualifiedStreamCount = 0;
  DateTime? lastQualifiedAt;

  /// Whether this entity has participated in at least one per-play standings
  /// observation during this reconstruction.
  bool hasRankObservation = false;

  /// Visible Top-200 rank from the immediately preceding per-play standings
  /// calculation. Null means the entity was outside the Top 200.
  int? lastObservedChartRank;

  int? livePeakRank;
  DateTime? livePeakAchievedAt;

  bool hasEnteredOfficialChartThisWeek = false;
  bool hasReenteredOfficialChartThisWeek = false;

  /// First moment in this replay at a Top 200 / Top 100 position.
  DateTime? firstChartedAt;
  DateTime? firstHot100At;

  bool _wasOfficiallyCharting = false;

  void observeRank({required int rank, required DateTime observedAt}) {
    if (livePeakRank == null || rank < livePeakRank!) {
      livePeakRank = rank;
      livePeakAchievedAt = observedAt.toUtc();
    }

    final isOfficiallyCharting = rank <= ChartRankingEngine.officialChartLimit;
    if (rank <= ChartRankingEngine.extendedStandingsLimit) {
      firstChartedAt ??= observedAt.toUtc();
    }
    if (isOfficiallyCharting) firstHot100At ??= observedAt.toUtc();

    if (isOfficiallyCharting) {
      if (!hasEnteredOfficialChartThisWeek) {
        hasEnteredOfficialChartThisWeek = true;
      } else if (!_wasOfficiallyCharting) {
        hasReenteredOfficialChartThisWeek = true;
      }
    }

    _wasOfficiallyCharting = isOfficiallyCharting;
    hasRankObservation = true;
    lastObservedChartRank = rank <= ChartRankingEngine.extendedStandingsLimit
        ? rank
        : null;
  }
}
