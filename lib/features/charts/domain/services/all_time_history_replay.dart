import '../models/chart_week.dart';
import 'chart_ranking_engine.dart';
import 'chart_week_resolver.dart';

/// Something a qualified play achieved on the all-time chart.
enum AllTimeAchievementType {
  /// First ever entry into the Top 200.
  debut,

  /// First ever entry into the Top 100 (after debuting below it).
  top100Entry,

  /// Back in the Top 200 at least a week after dropping out.
  reentry,

  /// A best-ever rank that also reaches a higher zone (Top 50, 25, 10, 5,
  /// 3 or 2) for the first time.
  newPeak,

  /// #1 for the first time.
  numberOne,

  /// #1 again, after losing it.
  returnsToNumberOne,

  /// A climb of at least [AllTimeHistoryReplay.bigClimbPlaces] places into
  /// the Top 100 with one play.
  bigClimb,
}

/// One achievement, at the play that caused it.
class AllTimeAchievement {
  const AllTimeAchievement({
    required this.type,
    required this.entityId,
    required this.playId,
    required this.occurredAt,
    required this.rank,
    required this.streams,
    this.previousRank,
    this.previousPeakRank,
    this.zone,
  });

  final AllTimeAchievementType type;
  final String entityId;

  /// The qualified play that caused it.
  final String playId;
  final DateTime occurredAt;
  final int rank;

  /// Lifetime qualified plays, including this one.
  final int streams;
  final int? previousRank;
  final int? previousPeakRank;

  /// For [AllTimeAchievementType.newPeak]: the zone it reached.
  final int? zone;

  /// Identical for the same achievement however often the history is
  /// replayed, so saving it twice is harmless.
  String deduplicationKey(String chartType) {
    final discriminator = switch (type) {
      AllTimeAchievementType.debut ||
      AllTimeAchievementType.top100Entry ||
      AllTimeAchievementType.numberOne => '',
      AllTimeAchievementType.newPeak => '$zone',
      AllTimeAchievementType.reentry ||
      AllTimeAchievementType.returnsToNumberOne ||
      AllTimeAchievementType.bigClimb => playId,
    };
    return 'alltime|$chartType|${type.name}|$entityId|$discriminator';
  }
}

/// Weeks an entity spent in each zone of the all-time chart.
class ZoneWeeks {
  const ZoneWeeks(this._weeks);

  /// Zones are cumulative: a week at #3 counts for the Top 3, Top 5,
  /// Top 10 and every larger zone.
  static const List<int> zones = [3, 5, 10, 25, 50, 75, 100, 200];

  final Map<int, int> _weeks;

  int weeksIn(int zone) => _weeks[zone] ?? 0;

  bool get isEmpty => _weeks.values.every((weeks) => weeks == 0);

  /// The smallest zone it has spent any week in, if any.
  int? get bestZone {
    for (final zone in zones) {
      if (weeksIn(zone) > 0) return zone;
    }
    return null;
  }
}

class AllTimeReplayResult {
  const AllTimeReplayResult({
    required this.achievements,
    required this.zoneWeeks,
    required this.observedWeeks,
    this.observedFromUtc,
  });

  final List<AllTimeAchievement> achievements;
  final Map<String, ZoneWeeks> zoneWeeks;

  /// Completed weeks the standings were counted at.
  final int observedWeeks;

  /// Start of the first counted week.
  final DateTime? observedFromUtc;

  ZoneWeeks zonesOf(String entityId) =>
      zoneWeeks[entityId] ?? const ZoneWeeks({});
}

/// Replays every qualified play in order and keeps the exact Top 200.
///
/// Ordering matches AllTimeChartRankingEngine (more plays first, then who
/// reached the total first, then id), so ranks agree with its accepted
/// peaks. Like those peaks, every entity that ever played is ranked,
/// including songs that are now blacklisted or removed.
///
/// From the same pass come:
/// - weeks in zones: the standings at the end of every completed chart
///   week (Sunday to Sunday, local time, as the weekly charts), each
///   counted once per week;
/// - achievements, at the exact play that caused them, from
///   [achievementsFromUtc] on.
class AllTimeHistoryReplay {
  const AllTimeHistoryReplay({
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
  }) : _weeks = weekResolver;

  final ChartWeekResolver _weeks;

  static const int standingsLimit = ChartRankingEngine.extendedStandingsLimit;
  static const int hot100 = ChartRankingEngine.officialChartLimit;

  /// Zones a new peak must reach to be worth a story.
  static const List<int> peakZones = [50, 25, 10, 5, 3, 2];

  static const int bigClimbPlaces = 15;

  /// A Top 200 return sooner than this after dropping out is ordinary churn
  /// at the bottom of the standings, not a re-entry story.
  static const Duration reentryAbsence = Duration(days: 7);

  AllTimeReplayResult run({
    required Iterable<ChartRankingEvent> events,
    required DateTime referenceLocal,
    DateTime? achievementsFromUtc,
    bool collectAchievements = true,
  }) {
    final ordered = events.toList(growable: false)
      ..sort((a, b) {
        final byTime = a.qualifiedAt.toUtc().compareTo(b.qualifiedAt.toUtc());
        return byTime != 0 ? byTime : a.entityId.compareTo(b.entityId);
      });

    final states = <String, _State>{};
    final top = <_State>[];
    final zones = <String, Map<int, int>>{};
    final achievements = <AllTimeAchievement>[];
    final from = achievementsFromUtc?.toUtc();
    final currentWeekStart = _weeks.resolve(referenceLocal).startUtc;

    ChartWeek? week;
    DateTime? observedFrom;
    var observedWeeks = 0;

    void closeWeeksBefore(DateTime instant) {
      while (week != null &&
          !week!.endUtc.isAfter(instant) &&
          !week!.endUtc.isAfter(currentWeekStart)) {
        observedFrom ??= week!.startUtc;
        observedWeeks++;
        for (var index = 0; index < top.length; index++) {
          final rank = index + 1;
          final counts = zones.putIfAbsent(top[index].entityId, () => {});
          for (final zone in ZoneWeeks.zones) {
            if (rank <= zone) counts[zone] = (counts[zone] ?? 0) + 1;
          }
        }
        week = _weeks.resolve(week!.endUtc.toLocal());
      }
    }

    for (final event in ordered) {
      final at = event.qualifiedAt.toUtc();
      week ??= _weeks.resolve(at.toLocal());
      closeWeeksBefore(at);

      final state = states.putIfAbsent(
        event.entityId,
        () => _State(event.entityId),
      );
      final previousIndex = state.inTop ? top.indexOf(state) : -1;
      final previousRank = previousIndex == -1 ? null : previousIndex + 1;

      if (previousIndex != -1) top.removeAt(previousIndex);
      state
        ..count += 1
        ..reachedAt = at;

      final position = _insertionPoint(top, state);
      int? rank;
      if (position < standingsLimit) {
        top.insert(position, state);
        state.inTop = true;
        rank = position + 1;
        if (top.length > standingsLimit) {
          top.removeLast()
            ..inTop = false
            ..leftTopAt = at;
        }
      } else {
        state.inTop = false;
      }

      if (rank != null) {
        if (collectAchievements && (from == null || !at.isBefore(from))) {
          final achievement = _achievementFor(
            state,
            rank: rank,
            previousRank: previousRank,
            playId: event.sourceEventId ?? '${event.entityId}@$at',
            at: at,
          );
          if (achievement != null) achievements.add(achievement);
        }
        state
          ..everInTop = true
          ..everTop100 = state.everTop100 || rank <= hot100
          ..everNumberOne = state.everNumberOne || rank == 1
          ..bestRank = state.bestRank == null || rank < state.bestRank!
              ? rank
              : state.bestRank;
      }
    }

    if (week != null) closeWeeksBefore(currentWeekStart);

    return AllTimeReplayResult(
      achievements: List.unmodifiable(achievements),
      zoneWeeks: {
        for (final MapEntry(key: id, value: counts) in zones.entries)
          id: ZoneWeeks(Map.unmodifiable(counts)),
      },
      observedWeeks: observedWeeks,
      observedFromUtc: observedFrom,
    );
  }

  AllTimeAchievement? _achievementFor(
    _State state, {
    required int rank,
    required int? previousRank,
    required String playId,
    required DateTime at,
  }) {
    AllTimeAchievement make(AllTimeAchievementType type, {int? zone}) =>
        AllTimeAchievement(
          type: type,
          entityId: state.entityId,
          playId: playId,
          occurredAt: at,
          rank: rank,
          streams: state.count,
          previousRank: previousRank,
          previousPeakRank: state.bestRank,
          zone: zone,
        );

    if (rank == 1 && previousRank != 1) {
      return make(
        state.everNumberOne
            ? AllTimeAchievementType.returnsToNumberOne
            : AllTimeAchievementType.numberOne,
      );
    }

    if (previousRank == null) {
      if (!state.everInTop) return make(AllTimeAchievementType.debut);
      final left = state.leftTopAt;
      final away = left == null ? Duration.zero : at.difference(left);
      return away >= reentryAbsence
          ? make(AllTimeAchievementType.reentry)
          : null;
    }

    if (!state.everTop100 && rank <= hot100) {
      return make(AllTimeAchievementType.top100Entry);
    }

    final best = state.bestRank;
    if (best != null && rank < best) {
      final zone = _zoneOf(rank);
      if (zone != null && zone != _zoneOf(best)) {
        return make(AllTimeAchievementType.newPeak, zone: zone);
      }
    }

    if (previousRank - rank >= bigClimbPlaces && rank <= hot100) {
      return make(AllTimeAchievementType.bigClimb);
    }

    return null;
  }

  static int? _zoneOf(int rank) {
    int? zone;
    for (final candidate in peakZones) {
      if (rank <= candidate) zone = candidate;
    }
    return zone;
  }

  /// Where [state] goes in [top]: after every entity with more plays, or
  /// as many that reached the total earlier.
  static int _insertionPoint(List<_State> top, _State state) {
    var low = 0;
    var high = top.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_ahead(top[middle], state)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static bool _ahead(_State a, _State b) {
    if (a.count != b.count) return a.count > b.count;
    final byTime = a.reachedAt!.compareTo(b.reachedAt!);
    if (byTime != 0) return byTime < 0;
    return a.entityId.compareTo(b.entityId) < 0;
  }
}

class _State {
  _State(this.entityId);

  final String entityId;
  int count = 0;
  DateTime? reachedAt;
  bool inTop = false;
  bool everInTop = false;
  bool everTop100 = false;
  bool everNumberOne = false;
  int? bestRank;
  DateTime? leftTopAt;
}
