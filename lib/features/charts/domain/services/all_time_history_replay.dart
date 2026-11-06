import '../models/chart_week.dart';
import 'chart_ranking_engine.dart';
import 'chart_week_resolver.dart';

/// Something a qualified play achieved on the all-time chart.
enum AllTimeAchievementType {
  /// First ever entry into the Top 200.
  debut,

  /// First ever entry into the Top 100 (after debuting below it). Under
  /// the SN-50 rules also when the same play reaches #1.
  top100Entry,

  /// Back in the Top 200 at least a week after dropping out. Under the
  /// SN-50 rules also when the same play reaches #1.
  reentry,

  /// A best-ever rank that also reaches a higher zone (Top 50, 25, 10, 5,
  /// 3 or 2) for the first time.
  newPeak,

  /// #1 for the first time.
  numberOne,

  /// #1 again, after losing it.
  returnsToNumberOne,

  /// A climb of at least [AllTimeHistoryReplay.bigClimbPlaces] places into
  /// the Top 100 with one play; from [AllTimeHistoryReplay.run]'s
  /// `everyClimbFromUtc` on, any climb at all (SN-50 complete coverage).
  bigClimb,

  /// The entity's qualified plays reached [AllTimeAchievement.milestone]
  /// (one of the replay's stream milestones).
  streamMilestone,

  /// The entity's group (its artist) gained a #1: [AllTimeAchievement.
  /// milestone] is how many of the group's entities have now been #1.
  careerNumberOne,

  /// The group's [AllTimeAchievement.milestone]th entity in the Top 10.
  careerTop10,

  /// The group's [AllTimeAchievement.milestone]th entity in the Top 100.
  careerTop100,

  /// First ever entry into the Top [AllTimeAchievement.zone] (one of
  /// [AllTimeHistoryReplay.thresholdZones]) after the debut.
  thresholdEntry,

  // App Update 1.1 (Moments chronicle), recorded only from the replay's
  // `chronicleFromUtc` on.

  /// Back in a zone it reached before ([AllTimeAchievement.zone], one of
  /// [AllTimeHistoryReplay.chronicleZones]), from below it.
  thresholdReturn,

  /// Back on the Hot 100 from Bubbling Under (#101-200) after charting on
  /// it before.
  hot100Return,

  /// Pushed from #100 to #101 by another entity's play: off the Hot 100,
  /// still on the Top 200. [AllTimeAchievement.milestone] is the completed
  /// chart days it finished on the Hot 100.
  hot100Exit,

  /// Pushed out of the Top 200 by another entity's play.
  /// [AllTimeAchievement.milestone] is the completed chart days it
  /// finished in the Top 200.
  chartExit,

  /// #1 at the close of a completed chart day (local midnight).
  /// [AllTimeAchievement.milestone] is the consecutive days at #1 ending
  /// that day; [AllTimeAchievement.cumulative] the days at #1 in all.
  numberOneDay,
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
    this.milestone,
    this.displacedEntityId,
    this.groupId,
    this.cumulative,
    this.sourceId,
  });

  final AllTimeAchievementType type;

  /// For [AllTimeAchievementType.numberOneDay]: every completed day the
  /// entity finished at #1, this one included. Not stored with the Moment.
  final int? cumulative;

  /// The source a Moment groups by, when it is not [playId]: an exit is
  /// caused by another entity's play, and a day close by no play at all,
  /// so neither joins that play's story.
  final String? sourceId;
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

  /// For stream milestones, the milestone; for career achievements, the
  /// ordinal (1 for a first).
  final int? milestone;

  /// For a #1: the entity that was #1 immediately before this play.
  final String? displacedEntityId;

  /// For career achievements: the group (artist) they count for.
  final String? groupId;

  /// Identical for the same achievement however often the history is
  /// replayed, so saving it twice is harmless.
  String deduplicationKey(String chartType) {
    final discriminator = switch (type) {
      AllTimeAchievementType.debut ||
      AllTimeAchievementType.top100Entry ||
      AllTimeAchievementType.numberOne => '',
      AllTimeAchievementType.newPeak ||
      AllTimeAchievementType.thresholdEntry => '$zone',
      AllTimeAchievementType.reentry ||
      AllTimeAchievementType.returnsToNumberOne ||
      AllTimeAchievementType.bigClimb => playId,
      AllTimeAchievementType.streamMilestone => '$milestone',
      AllTimeAchievementType.careerNumberOne ||
      AllTimeAchievementType.careerTop10 ||
      AllTimeAchievementType.careerTop100 => '',
      AllTimeAchievementType.thresholdReturn => '$zone|$playId',
      AllTimeAchievementType.hot100Return ||
      AllTimeAchievementType.hot100Exit ||
      AllTimeAchievementType.chartExit ||
      AllTimeAchievementType.numberOneDay => playId,
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

/// One completed chart day's standing of an entity (App Update 1.1): its
/// rank at the day's close (local midnight), or null when it finished the
/// day outside the Top 200.
class ChartDayStanding {
  const ChartDayStanding({required this.dayStartLocal, required this.rank});

  /// Local midnight starting the day.
  final DateTime dayStartLocal;
  final int? rank;
}

/// Completed chart days an entity finished in each place (App Update 1.1).
class ChartDayTotals {
  const ChartDayTotals({
    this.numberOneDays = 0,
    this.hot100Days = 0,
    this.chartDays = 0,
    this.numberOneRun = 0,
    this.hot100Run = 0,
    this.chartRun = 0,
    this.longestNumberOneRun = 0,
  });

  /// Completed days finished at #1, on the Hot 100 and in the Top 200.
  final int numberOneDays;
  final int hot100Days;
  final int chartDays;

  /// The current runs: consecutive days, ending with the last completed
  /// day, at #1, on the Hot 100 and in the Top 200 (0: not now).
  final int numberOneRun;
  final int hot100Run;
  final int chartRun;
  final int longestNumberOneRun;
}

class AllTimeReplayResult {
  const AllTimeReplayResult({
    required this.achievements,
    required this.zoneWeeks,
    required this.observedWeeks,
    this.observedFromUtc,
    this.dayTotals = const {},
    this.dayStandings = const {},
    this.observedDays = 0,
    this.trackedPeaks = const {},
    this.trackedFirstCharted = const {},
    this.trackedRanks = const {},
  });

  /// For the replay's `collectDayStandings` entities: the best Top 200 rank
  /// ever reached (at any play, not only at day closes), when it first
  /// entered the Top 200, and its rank after the last play (null: outside).
  final Map<String, int> trackedPeaks;
  final Map<String, DateTime> trackedFirstCharted;
  final Map<String, int?> trackedRanks;

  /// Per entity, its completed chart days (App Update 1.1).
  final Map<String, ChartDayTotals> dayTotals;

  /// Per entity, its rank at every completed day close since it first
  /// charted, oldest first: only for the replay's `collectDayStandings`
  /// (one entity's chart journey).
  final Map<String, List<ChartDayStanding>> dayStandings;

  /// Completed chart days closed.
  final int observedDays;

  ChartDayTotals daysOf(String entityId) =>
      dayTotals[entityId] ?? const ChartDayTotals();

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

  /// Zones whose first entry is told on its own (SN-50 F-Q14). The Top
  /// 100 is [AllTimeAchievementType.top100Entry]; #1 is its own story.
  static const List<int> thresholdZones = [
    75,
    50,
    40,
    30,
    25,
    20,
    15,
    10,
    5,
    3,
    2,
  ];

  static const int bigClimbPlaces = 15;

  /// Zones whose returns the Moments chronicle tells (App Update 1.1).
  static const List<int> chronicleZones = [50, 25, 20, 15, 10, 5, 3];

  /// An exit is told only for an entity that finished at least this many
  /// completed days on the chart it leaves: a song passing through for a
  /// few hours is churn, not news.
  static const int exitMinimumDays = 1;

  /// Local midnight starting the day of [local].
  static DateTime dayStartOf(DateTime local) =>
      DateTime(local.year, local.month, local.day);

  /// Local midnight ending the day starting at [dayStartLocal] (calendar
  /// arithmetic, so a daylight-saving day is still one day).
  static DateTime dayEndOf(DateTime dayStartLocal) =>
      DateTime(dayStartLocal.year, dayStartLocal.month, dayStartLocal.day + 1);

  static String dayKey(DateTime dayStartLocal) =>
      '${dayStartLocal.year.toString().padLeft(4, '0')}-'
      '${dayStartLocal.month.toString().padLeft(2, '0')}-'
      '${dayStartLocal.day.toString().padLeft(2, '0')}';

  /// A Top 200 return sooner than this after dropping out is ordinary churn
  /// at the bottom of the standings, not a re-entry story.
  static const Duration reentryAbsence = Duration(days: 7);

  /// Replays [events] and returns the standings' history.
  ///
  /// With [streamMilestones], reaching each of them is an achievement. With
  /// [groupOf] (an entity's artist), an entity's first #1, first Top 10 and
  /// first Top 100 also count for its group, with the group's ordinal: its
  /// first, second, … #1. Groups are counted over the whole history, also
  /// before [achievementsFromUtc]; entities without a group never count.
  /// From [thresholdEntriesFromUtc] on, every first entry into one of the
  /// [thresholdZones] after the debut is an achievement as well, and a #1
  /// never hides the Top 100 entry or re-entry it makes (SN-50 R3).
  /// From [everyClimbFromUtc] on, every play that moves its entity up is
  /// also a climb ([AllTimeAchievementType.bigClimb]), however small, beside
  /// whatever else that play achieved; ranks are never changed by it.
  AllTimeReplayResult run({
    required Iterable<ChartRankingEvent> events,
    required DateTime referenceLocal,
    DateTime? achievementsFromUtc,
    DateTime? thresholdEntriesFromUtc,
    DateTime? everyClimbFromUtc,
    bool collectAchievements = true,
    List<int> streamMilestones = const [],
    String? Function(String entityId)? groupOf,
    DateTime? chronicleFromUtc,
    Set<String> collectDayStandings = const {},
  }) {
    final chronicleFrom = chronicleFromUtc?.toUtc();
    // Chart days close at local midnight; only days that ended by the
    // start of today (from [referenceLocal]) are complete.
    final todayStart = dayStartOf(referenceLocal.toLocal());
    final days = <String, _DayCount>{};
    final standings = <String, List<ChartDayStanding>>{};
    DateTime? day;
    var observedDays = 0;
    String? leaderYesterday;
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
    final milestones = streamMilestones.toSet();
    final groupNumberOnes = <String, int>{};
    final groupTop10 = <String, int>{};
    final groupTop100 = <String, int>{};

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

    void closeDaysBefore(DateTime instant) {
      while (day != null) {
        final end = dayEndOf(day!);
        if (end.isAfter(instant.toLocal()) || end.isAfter(todayStart)) break;
        observedDays++;
        final leader = top.isEmpty ? null : top.first;
        final inTop = <String>{};
        for (var index = 0; index < top.length; index++) {
          final state = top[index];
          inTop.add(state.entityId);
          final count = days.putIfAbsent(state.entityId, _DayCount.new)
            ..chart += 1
            ..chartRun += 1;
          if (index < hot100) {
            count
              ..hot100 += 1
              ..hot100Run += 1;
          } else {
            count.hot100Run = 0;
          }
          if (collectDayStandings.contains(state.entityId)) {
            standings
                .putIfAbsent(state.entityId, () => [])
                .add(ChartDayStanding(dayStartLocal: day!, rank: index + 1));
          }
        }
        for (final MapEntry(key: id, value: count) in days.entries) {
          if (!inTop.contains(id)) {
            count
              ..chartRun = 0
              ..hot100Run = 0;
            if (collectDayStandings.contains(id)) {
              standings
                  .putIfAbsent(id, () => [])
                  .add(ChartDayStanding(dayStartLocal: day!, rank: null));
            }
          }
          if (id != leader?.entityId) count.numberOneRun = 0;
        }
        if (leader != null) {
          final count = days[leader.entityId]!;
          count
            ..numberOne += 1
            ..numberOneRun = leaderYesterday == leader.entityId
                ? count.numberOneRun + 1
                : 1;
          if (count.numberOneRun > count.longestNumberOneRun) {
            count.longestNumberOneRun = count.numberOneRun;
          }
          final closedAt = end.toUtc();
          if (collectAchievements &&
              chronicleFrom != null &&
              !closedAt.isBefore(chronicleFrom) &&
              (from == null || !closedAt.isBefore(from))) {
            final key = 'day:${dayKey(day!)}';
            achievements.add(
              AllTimeAchievement(
                type: AllTimeAchievementType.numberOneDay,
                entityId: leader.entityId,
                playId: key,
                sourceId: key,
                occurredAt: closedAt,
                rank: 1,
                streams: leader.count,
                previousRank: 1,
                previousPeakRank: 1,
                milestone: count.numberOneRun,
                cumulative: count.numberOne,
              ),
            );
          }
        }
        leaderYesterday = leader?.entityId;
        day = end;
      }
    }

    for (final event in ordered) {
      final at = event.qualifiedAt.toUtc();
      week ??= _weeks.resolve(at.toLocal());
      closeWeeksBefore(at);
      day ??= dayStartOf(at.toLocal());
      closeDaysBefore(at);

      final state = states.putIfAbsent(
        event.entityId,
        () => _State(event.entityId),
      );
      final previousIndex = state.inTop ? top.indexOf(state) : -1;
      final previousRank = previousIndex == -1 ? null : previousIndex + 1;
      final previousLeader = top.isEmpty ? null : top.first.entityId;

      if (previousIndex != -1) top.removeAt(previousIndex);
      state
        ..count += 1
        ..reachedAt = at;

      final position = _insertionPoint(top, state);
      final playId = event.sourceEventId ?? '${event.entityId}@$at';
      final collecting =
          collectAchievements && (from == null || !at.isBefore(from));
      final chronicling =
          collecting && chronicleFrom != null && !at.isBefore(chronicleFrom);

      // App Update 1.1: whoever this play pushes off the Hot 100 or out of
      // the Top 200, at this play, with its completed days there.
      AllTimeAchievement exit(
        _State left,
        AllTimeAchievementType type, {
        required int previousRank,
        required int rank,
        required int days,
      }) => AllTimeAchievement(
        type: type,
        entityId: left.entityId,
        playId: playId,
        sourceId: 'exit:$playId:${left.entityId}',
        occurredAt: at,
        rank: rank,
        streams: left.count,
        previousRank: previousRank,
        previousPeakRank: left.bestRank,
        milestone: days,
      );
      if (chronicling &&
          position < hot100 &&
          top.length >= hot100 &&
          (previousRank == null || previousRank > hot100)) {
        final left = top[hot100 - 1];
        final hot100Days = days[left.entityId]?.hot100 ?? 0;
        if (hot100Days >= exitMinimumDays) {
          achievements.add(
            exit(
              left,
              AllTimeAchievementType.hot100Exit,
              previousRank: hot100,
              rank: hot100 + 1,
              days: hot100Days,
            ),
          );
        }
      }

      int? rank;
      if (position < standingsLimit) {
        top.insert(position, state);
        state.inTop = true;
        rank = position + 1;
        if (top.length > standingsLimit) {
          final left = top.removeLast()
            ..inTop = false
            ..leftTopAt = at;
          final chartDays = days[left.entityId]?.chart ?? 0;
          if (chronicling && chartDays >= exitMinimumDays) {
            achievements.add(
              exit(
                left,
                AllTimeAchievementType.chartExit,
                previousRank: standingsLimit,
                rank: 0,
                days: chartDays,
              ),
            );
          }
        }
      } else {
        state.inTop = false;
      }

      if (chronicling && rank != null && previousRank != null) {
        final best = state.bestRank;
        if (state.everTop100 && rank <= hot100 && previousRank > hot100) {
          achievements.add(
            _make(
              state,
              AllTimeAchievementType.hot100Return,
              rank: rank,
              previousRank: previousRank,
              playId: playId,
              at: at,
            ),
          );
        }
        for (final zone in chronicleZones) {
          if (best != null &&
              best <= zone &&
              rank <= zone &&
              previousRank > zone) {
            achievements.add(
              _make(
                state,
                AllTimeAchievementType.thresholdReturn,
                rank: rank,
                previousRank: previousRank,
                playId: playId,
                at: at,
                zone: zone,
              ),
            );
          }
        }
      }

      AllTimeAchievement extra(
        AllTimeAchievementType type,
        int milestone, {
        String? groupId,
      }) => AllTimeAchievement(
        type: type,
        entityId: state.entityId,
        playId: playId,
        occurredAt: at,
        // 0 when outside the standings (a stream milestone can be).
        rank: rank ?? 0,
        streams: state.count,
        previousRank: previousRank,
        previousPeakRank: state.bestRank,
        milestone: milestone,
        groupId: groupId,
      );

      if (rank != null) {
        if (collecting) {
          final thresholdsFrom = thresholdEntriesFromUtc?.toUtc();
          final refined =
              thresholdsFrom != null && !at.isBefore(thresholdsFrom);
          if (refined && rank == 1 && previousRank != 1) {
            // A debut at #1 is told by the #1 itself.
            final entry = _entryFor(
              state,
              rank: rank,
              previousRank: previousRank,
              playId: playId,
              at: at,
            );
            if (entry != null && entry.type != AllTimeAchievementType.debut) {
              achievements.add(entry);
            }
          }
          final achievement = _achievementFor(
            state,
            rank: rank,
            previousRank: previousRank,
            playId: playId,
            at: at,
            previousLeader: previousLeader,
          );
          if (achievement != null) achievements.add(achievement);

          // SN-50 complete coverage: every real move up is told, once per
          // play (the same key as a big climb, so never twice).
          final climbsFrom = everyClimbFromUtc?.toUtc();
          if (climbsFrom != null &&
              !at.isBefore(climbsFrom) &&
              previousRank != null &&
              rank < previousRank &&
              achievement?.type != AllTimeAchievementType.bigClimb) {
            achievements.add(
              _make(
                state,
                AllTimeAchievementType.bigClimb,
                rank: rank,
                previousRank: previousRank,
                playId: playId,
                at: at,
              ),
            );
          }

          if (state.everInTop && refined) {
            for (final zone in thresholdZones) {
              final best = state.bestRank;
              if (rank > zone || (best != null && best <= zone)) continue;
              achievements.add(
                AllTimeAchievement(
                  type: AllTimeAchievementType.thresholdEntry,
                  entityId: state.entityId,
                  playId: playId,
                  occurredAt: at,
                  rank: rank,
                  streams: state.count,
                  previousRank: previousRank,
                  previousPeakRank: best,
                  zone: zone,
                ),
              );
            }
          }
        }

        // Career ordinals count the whole history, stories or not.
        final group = groupOf?.call(state.entityId);
        if (group != null) {
          for (final (zone, reached, counts, type) in [
            (
              1,
              state.everNumberOne,
              groupNumberOnes,
              AllTimeAchievementType.careerNumberOne,
            ),
            (
              10,
              state.everTop10,
              groupTop10,
              AllTimeAchievementType.careerTop10,
            ),
            (
              hot100,
              state.everTop100,
              groupTop100,
              AllTimeAchievementType.careerTop100,
            ),
          ]) {
            if (rank > zone || reached) continue;
            final ordinal = (counts[group] ?? 0) + 1;
            counts[group] = ordinal;
            if (collecting) {
              achievements.add(extra(type, ordinal, groupId: group));
            }
          }
        }

        state
          ..firstInTopAt ??= at
          ..everInTop = true
          ..everTop100 = state.everTop100 || rank <= hot100
          ..everTop10 = state.everTop10 || rank <= 10
          ..everNumberOne = state.everNumberOne || rank == 1
          ..bestRank = state.bestRank == null || rank < state.bestRank!
              ? rank
              : state.bestRank;
      }

      if (collecting && milestones.contains(state.count)) {
        achievements.add(
          extra(AllTimeAchievementType.streamMilestone, state.count),
        );
      }
    }

    if (week != null) closeWeeksBefore(currentWeekStart);
    if (day != null) closeDaysBefore(todayStart.toUtc());

    return AllTimeReplayResult(
      dayTotals: {
        for (final MapEntry(key: id, value: count) in days.entries)
          id: ChartDayTotals(
            numberOneDays: count.numberOne,
            hot100Days: count.hot100,
            chartDays: count.chart,
            numberOneRun: count.numberOneRun,
            hot100Run: count.hot100Run,
            chartRun: count.chartRun,
            longestNumberOneRun: count.longestNumberOneRun,
          ),
      },
      dayStandings: {
        for (final MapEntry(key: id, value: list) in standings.entries)
          id: List.unmodifiable(list),
      },
      trackedPeaks: {
        for (final id in collectDayStandings)
          id: ?states[id]?.bestRank,
      },
      trackedFirstCharted: {
        for (final id in collectDayStandings)
          id: ?states[id]?.firstInTopAt,
      },
      trackedRanks: {
        for (final id in collectDayStandings)
          if (states.containsKey(id))
            id: states[id]!.inTop ? top.indexOf(states[id]!) + 1 : null,
      },
      observedDays: observedDays,
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
    String? previousLeader,
  }) {
    AllTimeAchievement make(
      AllTimeAchievementType type, {
      int? zone,
      String? displaced,
    }) => _make(
      state,
      type,
      rank: rank,
      previousRank: previousRank,
      playId: playId,
      at: at,
      zone: zone,
      displaced: displaced,
    );

    if (rank == 1 && previousRank != 1) {
      return make(
        state.everNumberOne
            ? AllTimeAchievementType.returnsToNumberOne
            : AllTimeAchievementType.numberOne,
        displaced: previousLeader == state.entityId ? null : previousLeader,
      );
    }

    final entry = _entryFor(
      state,
      rank: rank,
      previousRank: previousRank,
      playId: playId,
      at: at,
    );
    if (entry != null || previousRank == null) return entry;

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

  /// The entry this play makes: a debut, a re-entry or a first Top 100.
  AllTimeAchievement? _entryFor(
    _State state, {
    required int rank,
    required int? previousRank,
    required String playId,
    required DateTime at,
  }) {
    AllTimeAchievement make(AllTimeAchievementType type) => _make(
      state,
      type,
      rank: rank,
      previousRank: previousRank,
      playId: playId,
      at: at,
    );

    if (previousRank == null) {
      if (!state.everInTop) return make(AllTimeAchievementType.debut);
      final left = state.leftTopAt;
      final away = left == null ? Duration.zero : at.difference(left);
      return away >= reentryAbsence
          ? make(AllTimeAchievementType.reentry)
          : null;
    }

    return !state.everTop100 && rank <= hot100
        ? make(AllTimeAchievementType.top100Entry)
        : null;
  }

  static AllTimeAchievement _make(
    _State state,
    AllTimeAchievementType type, {
    required int rank,
    required int? previousRank,
    required String playId,
    required DateTime at,
    int? zone,
    String? displaced,
  }) => AllTimeAchievement(
    type: type,
    entityId: state.entityId,
    playId: playId,
    occurredAt: at,
    rank: rank,
    streams: state.count,
    previousRank: previousRank,
    previousPeakRank: state.bestRank,
    zone: zone,
    displacedEntityId: displaced,
  );

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
  bool everTop10 = false;
  bool everNumberOne = false;
  int? bestRank;
  DateTime? leftTopAt;
  DateTime? firstInTopAt;
}

class _DayCount {
  int numberOne = 0;
  int hot100 = 0;
  int chart = 0;
  int numberOneRun = 0;
  int hot100Run = 0;
  int chartRun = 0;
  int longestNumberOneRun = 0;
}
