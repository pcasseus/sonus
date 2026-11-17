// Live-week RE-ENTRY (user decision 2026-11-16).
//
// Official RE-ENTRY derives from finalized chart history only. Leaving and
// returning within the same provisional live week never makes an entry a
// RE-ENTRY: a song with no finalized history stays NEW (provisional), and a
// song with finalized history keeps the comparison its finalized weeks give.
// Career standings keep their continuous-chart movement, measured from the
// standings at the comparison start.
//
// Everything runs through the real ChartRankingEngine,
// AllTimeChartRankingEngine and ChartMomentLiveDetector.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranked_entity.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranking_history.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_live_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rank_observation.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_movement.dart';

const song = 'target';

final weekStart = DateTime.utc(2026, 11, 15);
final weekEnd = DateTime.utc(2026, 11, 22);

void main() {
  const engine = ChartRankingEngine();

  group('weekly live chart: repeated intraday boundary crossings', () {
    test('no finalized history: in and out of the Hot 100 three times, '
        'still NEW and provisional', () {
      final plays = _Crossings(competitors: 101, rounds: 3);
      final result = engine.rank(events: plays.events);
      final entry = _target(result);

      expect(plays.timesPushedOut, 3);
      expect(entry.rank, 1);
      expect(entry.hasReenteredOfficialChartThisWeek, isTrue);
      expect(entry.movement, ChartMovement.newEntry);

      final m = _rowMovement(entry);
      expect(m.kind, ChartMoveKind.debut);
      expect(m.shortLabel, 'NEW');
      expect(m.achievement, ChartAchievement.newEntry);
      expect(m.provisional, isTrue);
    });

    test('no finalized history: finishing outside after crossings is NEW, '
        'never RE-ENTRY', () {
      final plays = _Crossings(competitors: 101, rounds: 3, finishOut: true);
      final entry = _target(engine.rank(events: plays.events));

      expect(entry.rank, 102);
      expect(entry.movement, ChartMovement.newEntry);
    });

    test('finalized history (last week #5): crossings keep the comparison '
        'with last week', () {
      final plays = _Crossings(competitors: 101, rounds: 3);
      final entry = _target(
        engine.rank(
          events: plays.events,
          historyByEntityId: const {
            song: ChartRankingHistory(
              entityId: song,
              finalizedWeeksOnChart: 4,
              hasEverCharted: true,
              previousFinalRank: 5,
              previousExtendedRank: 5,
              peakRank: 3,
            ),
          },
        ),
      );

      expect(entry.rank, 1);
      expect(entry.movement, ChartMovement.up);
      final m = _rowMovement(entry);
      expect(m.kind, ChartMoveKind.up);
      expect(m.shortLabel, '+4');
    });

    test('finalized history, absent last week: RE-ENTRY comes from the '
        'finalized absence, whatever the crossings', () {
      const history = {
        song: ChartRankingHistory(
          entityId: song,
          finalizedWeeksOnChart: 2,
          hasEverCharted: true,
          peakRank: 40,
        ),
      };
      for (final rounds in [0, 1, 3]) {
        final plays = _Crossings(competitors: 101, rounds: rounds);
        final entry = _target(
          engine.rank(events: plays.events, historyByEntityId: history),
        );
        expect(entry.movement, ChartMovement.reentry, reason: '$rounds');
        expect(_rowMovement(entry).shortLabel, 'RE-ENTRY');
      }
    });
  });

  group('live Moments: no lifecycle entry from intraday crossings', () {
    test('no finalized history: one debut, no re-entry, across three Top '
        '200 dips', () {
      final plays = _Crossings(competitors: 200, rounds: 3);
      final events = _liveEvents(engine, plays.events);

      expect(plays.timesPushedOut, 3);
      expect(_count(events, ChartMomentEventType.debut), 1);
      expect(_count(events, ChartMomentEventType.reentry), 0);
    });

    test('in last finalized week\'s Top 200: dips and returns make no debut '
        'or re-entry', () {
      final plays = _Crossings(competitors: 200, rounds: 3);
      final events = _liveEvents(
        engine,
        plays.events,
        history: const {
          song: ChartRankingHistory(
            entityId: song,
            finalizedWeeksOnChart: 3,
            hasEverCharted: true,
            previousFinalRank: 60,
            previousExtendedRank: 60,
            peakRank: 12,
          ),
        },
      );

      expect(_count(events, ChartMomentEventType.debut), 0);
      expect(_count(events, ChartMomentEventType.reentry), 0);
    });

    test('a genuine return after a finalized week away is one re-entry, '
        'not one per crossing', () {
      final plays = _Crossings(competitors: 200, rounds: 3);
      final events = _liveEvents(
        engine,
        plays.events,
        history: const {
          song: ChartRankingHistory(
            entityId: song,
            finalizedWeeksOnChart: 2,
            hasEverCharted: true,
            peakRank: 30,
          ),
        },
      );

      expect(_count(events, ChartMomentEventType.debut), 0);
      expect(_count(events, ChartMomentEventType.reentry), 1);
    });
  });

  group('career standings: continuous movement from the comparison start', () {
    const career = AllTimeChartRankingEngine();
    final cutoff = weekStart;

    test('never charted before: in and out of the Hot 100 this week is '
        'NEW', () {
      final events = _CareerCrossings(cutoff: cutoff).events;
      final entry = career
          .rank(events: events, comparisonStartUtc: cutoff)
          .firstWhere((e) => e.entityId == song);

      expect(entry.rank, 1);
      expect(entry.previousRank, isNull);
      expect(entry.movement, ChartMovement.newEntry);
    });

    test('on the chart at the comparison start: crossings this week are '
        'plain movement, never RE-ENTRY', () {
      final events = _CareerCrossings(
        cutoff: cutoff,
        chartedBefore: true,
      ).events;
      final entry = career
          .rank(events: events, comparisonStartUtc: cutoff)
          .firstWhere((e) => e.entityId == song);

      expect(entry.previousRank, 1);
      expect(entry.rank, 1);
      expect(entry.movement, ChartMovement.same);
    });

    test('a genuine return after a finalized week outside the Top 200 is '
        'RE-ENTRY', () {
      final early = cutoff.subtract(const Duration(days: 10));
      final events = <ChartRankingEvent>[
        _event(song, early),
        // 200 songs with two plays each push it out before the week.
        for (var i = 0; i < 200; i++) ...[
          _event(_competitor(i), early.add(Duration(minutes: 1 + i))),
          _event(_competitor(i), early.add(Duration(hours: 5, minutes: i))),
        ],
        for (var i = 0; i < 5; i++)
          _event(song, cutoff.add(Duration(hours: 1, minutes: i))),
      ];
      final entry = career
          .rank(events: events, comparisonStartUtc: cutoff)
          .firstWhere((e) => e.entityId == song);

      expect(entry.previousRank, isNull);
      expect(entry.rank, 1);
      expect(entry.movement, ChartMovement.reentry);
    });
  });
}

// ---------------------------------------------------------------------------

String _competitor(int index) =>
    'competitor-${index.toString().padLeft(3, '0')}';

ChartRankingEvent _event(String id, DateTime at, {String? source}) =>
    ChartRankingEvent(entityId: id, qualifiedAt: at, sourceEventId: source);

/// A target that takes #1, is pushed out by [competitors] later songs with
/// as many plays, and returns with one more play, [rounds] times in one
/// week. With 101 competitors it falls to #102 (out of the Hot 100), with
/// 200 to #201 (out of the Top 200).
class _Crossings {
  _Crossings({
    required int competitors,
    required int rounds,
    bool finishOut = false,
  }) {
    var minute = 0;
    DateTime next() => weekStart.add(Duration(minutes: ++minute));
    void push() {
      for (var i = 0; i < competitors; i++) {
        events.add(_event(_competitor(i), next(), source: 'p$minute'));
      }
      timesPushedOut++;
    }

    events.add(_event(song, next(), source: 'p$minute'));
    for (var round = 0; round < rounds; round++) {
      push();
      events.add(_event(song, next(), source: 'p$minute'));
    }
    if (finishOut) {
      push();
      timesPushedOut--;
    }
  }

  final events = <ChartRankingEvent>[];
  int timesPushedOut = 0;
}

/// The career version: equal totals keep the incumbent ahead, so pushers
/// need more plays than the target.
class _CareerCrossings {
  _CareerCrossings({required DateTime cutoff, bool chartedBefore = false}) {
    var minute = 0;
    DateTime next() => cutoff.add(Duration(minutes: ++minute));
    if (chartedBefore) {
      events.add(_event(song, cutoff.subtract(const Duration(days: 3))));
    }
    var target = chartedBefore ? 1 : 0;
    var others = 0;
    void playTarget(int times) {
      for (var i = 0; i < times; i++) {
        events.add(_event(song, next()));
      }
      target += times;
    }

    void push() {
      final add = target + 1 - others;
      for (var c = 0; c < 101; c++) {
        for (var i = 0; i < add; i++) {
          events.add(_event(_competitor(c), next()));
        }
      }
      others += add;
    }

    if (!chartedBefore) playTarget(1);
    for (var round = 0; round < 3; round++) {
      push();
      playTarget(others - target + 1);
    }
  }

  final events = <ChartRankingEvent>[];
}

ChartRankedEntity _target(List<ChartRankedEntity> result) =>
    result.firstWhere((entry) => entry.entityId == song);

/// What the live row shows, as the snapshot builder maps the entry.
ChartEntryMovement _rowMovement(ChartRankedEntity e) => ChartEntryMovement.of(
  ChartEntry(
    entity: const ChartEntitySnapshot(
      entityId: song,
      title: song,
      artistName: 'Artist',
    ),
    rank: e.rank,
    qualifiedStreamCount: e.qualifiedStreamCount,
    lastQualifiedAt: e.lastQualifiedAt,
    peakRank: e.peakRank,
    peakAchievedAt: e.peakAchievedAt,
    weeksOnChart: e.weeksOnChart,
    movement: e.movement,
    previousFinalRank: e.previousFinalRank,
    previousExtendedRank: e.previousExtendedRank,
    priorPeakRank: e.priorPeakRank,
    firstChartedAt: e.firstChartedAt,
    firstHot100At: e.firstHot100At,
  ),
  live: true,
  now: weekEnd.subtract(const Duration(hours: 1)),
);

List<ChartMomentEvent> _liveEvents(
  ChartRankingEngine engine,
  List<ChartRankingEvent> events, {
  Map<String, ChartRankingHistory> history = const {},
}) {
  const detector = ChartMomentLiveDetector();
  final observations = <ChartMomentRankObservation>[];
  engine.rank(
    events: events,
    historyByEntityId: history,
    onRankObservation: (o) {
      if (o.entityId == song) observations.add(o);
    },
  );
  return [
    for (final observation in observations)
      ...detector.detectRankTransition(
        chartType: ChartType.songs,
        entity: const ChartEntitySnapshot(
          entityId: song,
          title: song,
          artistName: 'Artist',
        ),
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        observation: observation,
        createdAt: weekEnd,
      ),
  ];
}

int _count(List<ChartMomentEvent> events, ChartMomentEventType type) =>
    events.where((e) => e.eventType == type).length;
