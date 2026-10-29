import '../../domain/entities/chart_snapshot.dart';

/// Official longevity on the finalized weekly chart, derived when the chart
/// loads from stored finalized weeks. Nothing here is stored or written
/// back (SN-50 E-Q10A/E-Q10B).
class ChartLongevity {
  const ChartLongevity({
    required this.weeksAtNumberOne,
    required this.longestNumberOneRun,
    required this.topTenStreak,
    required this.officialWeeks,
    this.debutWeekStartUtc,
    this.debutRank,
  });

  /// Finalized weeks at #1.
  final int weeksAtNumberOne;

  /// The most consecutive finalized weeks at #1.
  final int longestNumberOneRun;

  /// Consecutive finalized weeks in the Top 10, up to the latest one.
  final int topTenStreak;

  /// Finalized weeks in the Top 100.
  final int officialWeeks;

  /// The first finalized week in the Top 100, and its position there.
  final DateTime? debutWeekStartUtc;
  final int? debutRank;

  bool get hasDebuted => debutWeekStartUtc != null && debutRank != null;
}

/// Longevity for every entity, as of each finalized week and as of the
/// latest one, built once per load from history.
class ChartLongevityIndex {
  ChartLongevityIndex._(this._byWeek, this._latest, this._extendedByWeek);

  static final ChartLongevityIndex empty = ChartLongevityIndex._(
    const {},
    const {},
    const {},
  );

  /// [history] holds finalized snapshots, in any order. Weeks count as
  /// consecutive only when one ends where the next begins.
  factory ChartLongevityIndex.fromHistory(List<ChartSnapshot> history) {
    final weeks = [...history]
      ..sort((a, b) => a.weekStartUtc.compareTo(b.weekStartUtc));
    final states = <String, _State>{};
    final byWeek = <DateTime, Map<String, ChartLongevity>>{};
    final extendedByWeek = <DateTime, Map<String, int>>{};

    for (var index = 0; index < weeks.length; index++) {
      final week = weeks[index];
      final start = week.weekStartUtc.toUtc();
      final follows = index > 0 && weeks[index - 1].weekEndUtc.toUtc() == start;

      if (follows) {
        extendedByWeek[start] = {
          for (final entry in weeks[index - 1].entries)
            if (entry.isOffChartStanding) entry.entity.entityId: entry.rank,
        };
      }

      for (final entry in week.entries) {
        if (!entry.isOfficiallyCharting) continue;
        states
            .putIfAbsent(entry.entity.entityId, _State.new)
            .add(index, start, entry.rank, follows: follows);
      }

      byWeek[start] = {
        for (final entry in week.entries)
          if (states[entry.entity.entityId] case final state?)
            entry.entity.entityId: state.asOf(index),
      };
    }

    final last = weeks.length - 1;

    return ChartLongevityIndex._(byWeek, {
      for (final MapEntry(:key, :value) in states.entries)
        key: value.asOf(last),
    }, extendedByWeek);
  }

  final Map<DateTime, Map<String, ChartLongevity>> _byWeek;
  final Map<String, ChartLongevity> _latest;
  final Map<DateTime, Map<String, int>> _extendedByWeek;

  /// As of the latest finalized week; null if it never made a Top 100.
  ChartLongevity? latest(String entityId) => _latest[entityId];

  /// As of the finalized week starting at [weekStartUtc].
  ChartLongevity? asOfWeek(DateTime weekStartUtc, String entityId) =>
      _byWeek[weekStartUtc.toUtc()]?[entityId];

  /// The #101–200 position the entity held in the week right before the
  /// one starting at [weekStartUtc], for context only (SN-50 E-Q1).
  int? previousExtendedRank(DateTime weekStartUtc, String entityId) =>
      _extendedByWeek[weekStartUtc.toUtc()]?[entityId];
}

class _State {
  int weeksAtNumberOne = 0;
  int numberOneRun = 0;
  int longestNumberOneRun = 0;
  int topTenRun = 0;
  int officialWeeks = 0;
  int? lastNumberOneIndex;
  int? lastTopTenIndex;
  DateTime? debutWeekStartUtc;
  int? debutRank;

  void add(int index, DateTime start, int rank, {required bool follows}) {
    officialWeeks++;
    debutWeekStartUtc ??= start;
    debutRank ??= rank;

    if (rank <= 10) {
      topTenRun = follows && lastTopTenIndex == index - 1 ? topTenRun + 1 : 1;
      lastTopTenIndex = index;
    }

    if (rank == 1) {
      weeksAtNumberOne++;
      numberOneRun = follows && lastNumberOneIndex == index - 1
          ? numberOneRun + 1
          : 1;
      lastNumberOneIndex = index;
      if (numberOneRun > longestNumberOneRun) {
        longestNumberOneRun = numberOneRun;
      }
    }
  }

  ChartLongevity asOf(int index) => ChartLongevity(
    weeksAtNumberOne: weeksAtNumberOne,
    longestNumberOneRun: longestNumberOneRun,
    topTenStreak: lastTopTenIndex == index ? topTenRun : 0,
    officialWeeks: officialWeeks,
    debutWeekStartUtc: debutWeekStartUtc,
    debutRank: debutRank,
  );
}
