import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranking_history.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

void main() {
  const engine = ChartRankingEngine();

  ChartRankingEvent event(String entityId, int hour, {int minute = 0}) {
    return ChartRankingEvent(
      entityId: entityId,
      qualifiedAt: DateTime.utc(2026, 9, 27, hour, minute),
    );
  }

  test('ranks by streams then most recent qualifying stream', () {
    final result = engine.rank(
      events: [
        event('song-a', 1),
        event('song-b', 2),
        event('song-a', 3),
        event('song-b', 4),
      ],
    );

    expect(result.map((entry) => entry.entityId), ['song-b', 'song-a']);
    expect(result[0].qualifiedStreamCount, 2);
    expect(result[1].qualifiedStreamCount, 2);
  });

  test('stable entity id is final tie breaker', () {
    final qualifiedAt = DateTime.utc(2026, 9, 27, 1);

    final result = engine.rank(
      events: [
        ChartRankingEvent(entityId: 'song-b', qualifiedAt: qualifiedAt),
        ChartRankingEvent(entityId: 'song-a', qualifiedAt: qualifiedAt),
      ],
    );

    expect(result.map((entry) => entry.entityId), ['song-a', 'song-b']);
  });

  test('preserves highest live position as peak even after sinking', () {
    final events = <ChartRankingEvent>[event('song-c', 1)];

    for (var index = 0; index < 6; index++) {
      events.add(event('song-${index + 1}', 2 + index));
      events.add(event('song-${index + 1}', 10 + index));
    }

    final result = engine.rank(events: events);

    final songC = result.firstWhere((entry) => entry.entityId == 'song-c');

    expect(songC.rank, greaterThan(1));
    expect(songC.peakRank, 1);
    expect(songC.peakAchievedAt, DateTime.utc(2026, 9, 27, 1));
  });

  test('can exclude provisional intraweek peak from returned career peak', () {
    final events = <ChartRankingEvent>[event('song-c', 1)];

    for (var index = 0; index < 6; index++) {
      events.add(event('song-${index + 1}', 2 + index));
      events.add(event('song-${index + 1}', 10 + index));
    }

    final result = engine.rank(
      events: events,
      includeObservedPeakInResult: false,
    );

    final songC = result.firstWhere((entry) => entry.entityId == 'song-c');

    expect(songC.rank, greaterThan(1));
    expect(songC.peakRank, songC.rank);
    expect(songC.peakAchievedAt, songC.lastQualifiedAt);
  });

  test(
    'final peak resolution still preserves an earlier finalized career peak',
    () {
      final events = <ChartRankingEvent>[event('song-c', 1)];

      for (var index = 0; index < 6; index++) {
        events.add(event('song-${index + 1}', 2 + index));
        events.add(event('song-${index + 1}', 10 + index));
      }

      final result = engine.rank(
        events: events,
        historyByEntityId: {
          'song-c': ChartRankingHistory(
            entityId: 'song-c',
            finalizedWeeksOnChart: 4,
            hasEverCharted: true,
            previousFinalRank: 8,
            previousExtendedRank: 8,
            peakRank: 2,
            peakAchievedAt: DateTime.utc(2026, 9, 20),
          ),
        },
        includeObservedPeakInResult: false,
      );

      final songC = result.firstWhere((entry) => entry.entityId == 'song-c');

      expect(songC.rank, greaterThan(2));
      expect(songC.peakRank, 2);
      expect(songC.peakAchievedAt, DateTime.utc(2026, 9, 20));
    },
  );
  test('uses previous finalized rank for live movement', () {
    final result = engine.rank(
      events: [event('song-a', 1), event('song-a', 2), event('song-b', 3)],
      historyByEntityId: const {
        'song-a': ChartRankingHistory(
          entityId: 'song-a',
          finalizedWeeksOnChart: 4,
          hasEverCharted: true,
          previousFinalRank: 8,
          peakRank: 2,
        ),
      },
    );

    final songA = result.firstWhere((entry) => entry.entityId == 'song-a');

    expect(songA.rank, 1);
    expect(songA.previousFinalRank, 8);
    expect(songA.movement, ChartMovement.up);
    expect(songA.weeksOnChart, 4);
    expect(songA.peakRank, 1);
  });

  test('historical charted entity without previous-week rank is reentry', () {
    final result = engine.rank(
      events: [event('song-a', 1)],
      historyByEntityId: const {
        'song-a': ChartRankingHistory(
          entityId: 'song-a',
          finalizedWeeksOnChart: 3,
          hasEverCharted: true,
        ),
      },
    );

    expect(result.single.movement, ChartMovement.reentry);
  });

  test('true first-time chart entity is new', () {
    final result = engine.rank(events: [event('song-a', 1)]);

    expect(result.single.movement, ChartMovement.newEntry);
  });

  test('only eligible entities appear in current standings', () {
    final result = engine.rank(
      events: [event('song-a', 1), event('song-a', 2), event('song-b', 3)],
      eligibleEntityIds: const {'song-b'},
    );

    expect(result, hasLength(1));
    expect(result.single.entityId, 'song-b');
  });

  test('returns at most 200 extended standings', () {
    final events = <ChartRankingEvent>[];

    for (var index = 0; index < 250; index++) {
      events.add(
        ChartRankingEvent(
          entityId: 'song-${index.toString().padLeft(3, '0')}',
          qualifiedAt: DateTime.utc(
            2026,
            9,
            27,
            1,
          ).add(Duration(seconds: index)),
        ),
      );
    }

    final result = engine.rank(events: events);

    expect(result, hasLength(200));
    expect(result.last.rank, 200);
  });
}
