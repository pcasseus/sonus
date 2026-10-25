import '../models/all_time_ranked_entity.dart';
import '../models/chart_movement.dart';
import 'chart_ranking_engine.dart';

/// Ranks entities by every qualified play they have ever received.
///
/// Totals never reset. Equal totals keep the entity that reached the total
/// first (the incumbent), then fall back to the entity id, so standings never
/// reorder without new listening.
///
/// Peaks and chart entry are replayed from every play, including plays of
/// songs that are now blocked or removed. A position an entity really held
/// stays its peak; blocking another song later never improves it.
class AllTimeChartRankingEngine {
  const AllTimeChartRankingEngine();

  /// [comparisonStartUtc] is when movement is measured from: the standings
  /// just before it are each entity's previous rank. [eligibleEntityIds]
  /// limits who is ranked now, not the history peaks are replayed from.
  List<AllTimeRankedEntity> rank({
    required Iterable<ChartRankingEvent> events,
    required DateTime comparisonStartUtc,
    Set<String>? eligibleEntityIds,
  }) {
    final ordered = events.toList(growable: false)..sort(_compareEvents);

    bool isEligible(_LifetimeState state) =>
        eligibleEntityIds == null || eligibleEntityIds.contains(state.entityId);

    final cutoff = comparisonStartUtc.toUtc();
    final states = <String, _LifetimeState>{};
    // Entities per total, so a rank is a count of totals at or above it.
    final totals = _CountTree(ordered.length);
    _Comparison? comparison;

    for (final event in ordered) {
      final at = event.qualifiedAt.toUtc();

      if (comparison == null && !at.isBefore(cutoff)) {
        comparison = _Comparison.of(states.values, isEligible);
      }

      final state = states.putIfAbsent(
        event.entityId,
        () => _LifetimeState(event.entityId),
      );

      if (state.count > 0) {
        totals.add(state.count, -1);
      }
      state
        ..count += 1
        ..reachedAt = at;
      totals.add(state.count, 1);

      // Everyone else on this total reached it no later than now, so they
      // stay ahead; only this play can improve this entity's rank.
      final rankNow = totals.atLeast(state.count);
      if (state.peakRank == null || rankNow < state.peakRank!) {
        state
          ..peakRank = rankNow
          ..peakAchievedAt = at;
      }
    }

    comparison ??= _Comparison.of(states.values, isEligible);

    final standings = _sortedStates(states.values.where(isEligible));
    final limit = standings.length < ChartRankingEngine.extendedStandingsLimit
        ? standings.length
        : ChartRankingEngine.extendedStandingsLimit;

    return List<AllTimeRankedEntity>.unmodifiable([
      for (var index = 0; index < limit; index++)
        _resultFor(standings[index], index + 1, comparison),
    ]);
  }

  static AllTimeRankedEntity _resultFor(
    _LifetimeState state,
    int rank,
    _Comparison comparison,
  ) {
    final previousRank = comparison.ranks[state.entityId];
    final peakRank = state.peakRank!;

    return AllTimeRankedEntity(
      entityId: state.entityId,
      rank: rank,
      lifetimeStreamCount: state.count,
      lastQualifiedAt: state.reachedAt!,
      peakRank: peakRank < rank ? peakRank : rank,
      peakAchievedAt: peakRank < rank
          ? state.peakAchievedAt!
          : state.reachedAt!,
      previousRank: previousRank,
      movement: _movementFor(
        rank: rank,
        previousRank: previousRank,
        hadCharted: comparison.charted.contains(state.entityId),
      ),
    );
  }

  static ChartMovement _movementFor({
    required int rank,
    required int? previousRank,
    required bool hadCharted,
  }) {
    if (previousRank == null) {
      return hadCharted ? ChartMovement.reentry : ChartMovement.newEntry;
    }
    if (rank < previousRank) {
      return ChartMovement.up;
    }
    if (rank > previousRank) {
      return ChartMovement.down;
    }
    return ChartMovement.same;
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

  static int _compareStates(_LifetimeState a, _LifetimeState b) {
    final countComparison = b.count.compareTo(a.count);
    if (countComparison != 0) {
      return countComparison;
    }
    final reachedComparison = a.reachedAt!.compareTo(b.reachedAt!);
    if (reachedComparison != 0) {
      return reachedComparison;
    }
    return a.entityId.compareTo(b.entityId);
  }
}

/// The standings at the comparison start.
class _Comparison {
  const _Comparison({required this.ranks, required this.charted});

  factory _Comparison.of(
    Iterable<_LifetimeState> states,
    bool Function(_LifetimeState) isEligible,
  ) {
    final standings = _sortedStates(states.where(isEligible));
    return _Comparison(
      ranks: {
        for (
          var index = 0;
          index < standings.length &&
              index < ChartRankingEngine.extendedStandingsLimit;
          index++
        )
          standings[index].entityId: index + 1,
      },
      // Peaks only improve, so a peak inside the standings means the entity
      // had charted at some point before the comparison start.
      charted: {
        for (final state in states)
          if (state.peakRank! <= ChartRankingEngine.extendedStandingsLimit)
            state.entityId,
      },
    );
  }

  /// Rank among eligible entities, within the extended standings.
  final Map<String, int> ranks;

  /// Entities that had been inside the extended standings before.
  final Set<String> charted;
}

List<_LifetimeState> _sortedStates(Iterable<_LifetimeState> states) =>
    states.toList(growable: false)
      ..sort(AllTimeChartRankingEngine._compareStates);

class _LifetimeState {
  _LifetimeState(this.entityId);

  final String entityId;

  int count = 0;
  DateTime? reachedAt;

  int? peakRank;
  DateTime? peakAchievedAt;
}

/// Fenwick tree of how many entities hold each total.
class _CountTree {
  _CountTree(this._maxCount) : _tree = List<int>.filled(_maxCount + 1, 0);

  final int _maxCount;
  final List<int> _tree;
  int _entities = 0;

  void add(int count, int delta) {
    _entities += delta;
    for (var i = count; i <= _maxCount; i += i & -i) {
      _tree[i] += delta;
    }
  }

  /// Entities whose total is at least [count].
  int atLeast(int count) => _entities - _below(count);

  int _below(int count) {
    var sum = 0;
    for (var i = count - 1; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }
}
