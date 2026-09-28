import '../models/chart_movement.dart';
import '../models/chart_ranked_entity.dart';
import '../models/chart_ranking_history.dart';

class ChartRankingEvent {
  const ChartRankingEvent({required this.entityId, required this.qualifiedAt});

  final String entityId;
  final DateTime qualifiedAt;
}

class ChartRankingEngine {
  const ChartRankingEngine();

  static const int officialChartLimit = 100;
  static const int extendedStandingsLimit = 200;

  List<ChartRankedEntity> rank({
    required Iterable<ChartRankingEvent> events,
    Map<String, ChartRankingHistory> historyByEntityId = const {},
    Set<String>? eligibleEntityIds,
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

        rankedState.observeRank(
          rank: rank,
          observedAt: event.qualifiedAt.toUtc(),
        );
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

      final resolvedPeakRank = _resolvedPeakRank(
        priorPeakRank: priorPeakRank,
        livePeakRank: state.livePeakRank,
        currentRank: rank,
      );

      final resolvedPeakAchievedAt = _resolvedPeakAchievedAt(
        resolvedPeakRank: resolvedPeakRank,
        priorPeakRank: priorPeakRank,
        priorPeakAchievedAt: priorPeakAchievedAt,
        livePeakRank: state.livePeakRank,
        livePeakAchievedAt: state.livePeakAchievedAt,
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

  static ChartMovement _movementFor({
    required _MutableChartState state,
    required int currentRank,
    required ChartRankingHistory? history,
  }) {
    if (state.hasReenteredOfficialChartThisWeek) {
      return ChartMovement.reentry;
    }

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

    return ChartMovement.newEntry;
  }
}

class _MutableChartState {
  _MutableChartState({required this.entityId, required this.history});

  final String entityId;
  final ChartRankingHistory? history;

  int qualifiedStreamCount = 0;
  DateTime? lastQualifiedAt;

  int? livePeakRank;
  DateTime? livePeakAchievedAt;

  bool hasEnteredOfficialChartThisWeek = false;
  bool hasReenteredOfficialChartThisWeek = false;

  bool _wasOfficiallyCharting = false;

  void observeRank({required int rank, required DateTime observedAt}) {
    if (livePeakRank == null || rank < livePeakRank!) {
      livePeakRank = rank;
      livePeakAchievedAt = observedAt.toUtc();
    }

    final isOfficiallyCharting = rank <= ChartRankingEngine.officialChartLimit;

    if (isOfficiallyCharting) {
      if (!hasEnteredOfficialChartThisWeek) {
        hasEnteredOfficialChartThisWeek = true;
      } else if (!_wasOfficiallyCharting) {
        hasReenteredOfficialChartThisWeek = true;
      }
    }

    _wasOfficiallyCharting = isOfficiallyCharting;
  }
}
