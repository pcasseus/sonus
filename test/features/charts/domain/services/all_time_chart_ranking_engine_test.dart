import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

/// Week 1: Sunday 2026-10-04 .. week 2 starts Sunday 2026-10-11 (UTC here).
final week1 = DateTime.utc(2026, 10, 4, 12);
final week2Start = DateTime.utc(2026, 10, 11);
final week2 = DateTime.utc(2026, 10, 12, 12);

List<ChartRankingEvent> plays(String id, int count, DateTime from) => [
  for (var i = 0; i < count; i++)
    ChartRankingEvent(
      entityId: id,
      qualifiedAt: from.add(Duration(minutes: i)),
      sourceEventId: '$id-${from.toIso8601String()}-$i',
    ),
];

void main() {
  const engine = AllTimeChartRankingEngine();

  group('lifetime totals', () {
    test('a #1 stays #1 across a week boundary with no new listening', () {
      final result = engine.rank(
        events: [
          ...plays('angel-wings', 43, week1),
          ...plays('bittersweet', 36, week1.add(const Duration(hours: 2))),
        ],
        comparisonStartUtc: week2Start,
      );

      expect(result.map((e) => e.entityId), ['angel-wings', 'bittersweet']);
      expect(result.map((e) => e.lifetimeStreamCount), [43, 36]);
      expect(result.first.rank, 1);
    });

    test('totals never reset at a week boundary', () {
      final result = engine.rank(
        events: [...plays('a', 10, week1), ...plays('a', 3, week2)],
        comparisonStartUtc: week2Start,
      );

      expect(result.single.lifetimeStreamCount, 13);
    });

    test('a song not played this week keeps its standing', () {
      final result = engine.rank(
        events: [
          ...plays('old-favourite', 20, week1),
          ...plays('new-song', 2, week2),
        ],
        comparisonStartUtc: week2Start,
      );

      expect(result.map((e) => e.entityId), ['old-favourite', 'new-song']);
    });

    test('a challenger overtakes only with a higher cumulative total', () {
      final tied = engine.rank(
        events: [
          ...plays('angel-wings', 43, week1),
          ...plays('bittersweet', 36, week1),
          ...plays('bittersweet', 7, week2),
        ],
        comparisonStartUtc: week2Start,
      );
      // 43 v 43: the incumbent, who reached 43 first, keeps #1.
      expect(tied.map((e) => e.entityId), ['angel-wings', 'bittersweet']);

      final ahead = engine.rank(
        events: [
          ...plays('angel-wings', 43, week1),
          ...plays('bittersweet', 36, week1),
          ...plays('bittersweet', 8, week2),
        ],
        comparisonStartUtc: week2Start,
      );
      expect(ahead.map((e) => e.entityId), ['bittersweet', 'angel-wings']);
      expect(ahead.first.lifetimeStreamCount, 44);
    });
  });

  group('deterministic ties', () {
    test('equal totals keep the entity that reached the total first', () {
      final result = engine.rank(
        events: [
          ...plays('later', 5, week1.add(const Duration(hours: 5))),
          ...plays('earlier', 5, week1),
        ],
        comparisonStartUtc: week2Start,
      );

      expect(result.map((e) => e.entityId), ['earlier', 'later']);
    });

    test('identical timing falls back to a stable id order', () {
      final at = week1;
      List<ChartRankingEvent> one(String id) => [
        ChartRankingEvent(entityId: id, qualifiedAt: at, sourceEventId: id),
      ];

      final first = engine.rank(
        events: [...one('b'), ...one('a'), ...one('c')],
        comparisonStartUtc: week2Start,
      );
      final second = engine.rank(
        events: [...one('c'), ...one('b'), ...one('a')],
        comparisonStartUtc: week2Start,
      );

      expect(first.map((e) => e.entityId), ['a', 'b', 'c']);
      expect(second.map((e) => e.entityId), ['a', 'b', 'c']);
    });
  });

  group('peak, movement and NEW', () {
    test('peak is the best all-time rank ever reached', () {
      final result = engine.rank(
        events: [
          ...plays('a', 3, week1), // a reaches #1
          ...plays('b', 5, week1.add(const Duration(hours: 1))),
        ],
        comparisonStartUtc: week2Start,
      );

      final a = result.firstWhere((e) => e.entityId == 'a');
      expect(a.rank, 2);
      expect(a.peakRank, 1);
      expect(a.peakAchievedAt, week1);
    });

    test(
      'movement compares with the all-time standings at the comparison start',
      () {
        final result = engine.rank(
          events: [
            ...plays('a', 5, week1),
            ...plays('b', 4, week1),
            ...plays('b', 2, week2),
            ...plays('c', 1, week2),
          ],
          comparisonStartUtc: week2Start,
        );

        final byId = {for (final e in result) e.entityId: e};
        expect(byId['b']!.previousRank, 2);
        expect(byId['b']!.rank, 1);
        expect(byId['b']!.movement, ChartMovement.up);
        expect(byId['a']!.previousRank, 1);
        expect(byId['a']!.movement, ChartMovement.down);
        expect(byId['c']!.previousRank, isNull);
        expect(byId['c']!.movement, ChartMovement.newEntry);
      },
    );

    test('unchanged standings read as no movement, never NEW', () {
      final result = engine.rank(
        events: plays('a', 2, week1),
        comparisonStartUtc: week2Start,
      );

      expect(result.single.movement, ChartMovement.same);
      expect(result.single.previousRank, 1);
    });

    test('a first appearance is NEW', () {
      final result = engine.rank(
        events: [...plays('a', 3, week1), ...plays('b', 1, week2)],
        comparisonStartUtc: week2Start,
      );

      expect(result.last.entityId, 'b');
      expect(result.last.movement, ChartMovement.newEntry);
    });

    test('a return to the standings is a re-entry, not NEW', () {
      final events = [
        // r charts at #1, then 200 others push it out before week 2.
        ...plays('r', 1, week1),
        for (var i = 0; i < 200; i++)
          ...plays(
            'o${i.toString().padLeft(3, '0')}',
            2,
            week1.add(const Duration(hours: 1)),
          ),
        // This week r climbs back in, and n arrives for the first time.
        ...plays('r', 2, week2),
        ...plays('n', 3, week2),
      ];

      final result = engine.rank(
        events: events,
        comparisonStartUtc: week2Start,
      );
      final byId = {for (final e in result) e.entityId: e};

      expect(byId['r']!.previousRank, isNull);
      expect(byId['r']!.movement, ChartMovement.reentry);
      expect(byId['r']!.peakRank, 1);
      expect(byId['n']!.movement, ChartMovement.newEntry);
    });
  });

  group('eligibility and limits', () {
    test('blocking a song never improves a peak earned behind it', () {
      // a really peaked at #2 behind x. Once x is blocked, a must not claim
      // a #1 it never held.
      final result = engine.rank(
        events: [
          ...plays('x', 10, week1),
          ...plays('a', 3, week1.add(const Duration(hours: 1))),
          ...plays('b', 5, week1.add(const Duration(hours: 2))),
        ],
        comparisonStartUtc: week2Start,
        eligibleEntityIds: {'a', 'b'},
      );

      final a = result.firstWhere((e) => e.entityId == 'a');
      expect(a.rank, 2);
      expect(a.peakRank, 2);
    });

    test('ineligible entities are left out without affecting others', () {
      final result = engine.rank(
        events: [...plays('blocked', 9, week1), ...plays('ok', 1, week1)],
        comparisonStartUtc: week2Start,
        eligibleEntityIds: {'ok'},
      );

      expect(result.single.entityId, 'ok');
      expect(result.single.rank, 1);
      expect(result.single.peakRank, 1);
    });

    test(
      'standings stop at the extended limit, on the same lifetime basis',
      () {
        final events = [
          for (var i = 0; i < 205; i++)
            ...plays('s${i.toString().padLeft(3, '0')}', 205 - i, week1),
        ];

        final result = engine.rank(
          events: events,
          comparisonStartUtc: week2Start,
        );

        expect(result, hasLength(ChartRankingEngine.extendedStandingsLimit));
        expect(result.first.lifetimeStreamCount, 205);
        expect(result[100].rank, 101);
        expect(result.last.lifetimeStreamCount, 6);
      },
    );

    test('no plays gives an empty ranking', () {
      expect(
        engine.rank(events: const [], comparisonStartUtc: week2Start),
        isEmpty,
      );
    });
  });
}
