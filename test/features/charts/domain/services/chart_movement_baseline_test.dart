import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranked_entity.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranking_history.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

/// SN-50 E-Q2 (C-4): last week's final official rank is the movement
/// baseline, whatever happened inside the week. E-Q7: the weekly and
/// lifetime tie-breaks stay different.
void main() {
  const engine = ChartRankingEngine();
  final weekStart = DateTime.utc(2026, 9, 27);

  ChartRankingEvent at(String entityId, Duration offset) =>
      ChartRankingEvent(entityId: entityId, qualifiedAt: weekStart.add(offset));

  String competitor(int index) =>
      'competitor-${index.toString().padLeft(3, '0')}';

  /// One stream each from 101 songs, later than everything before, which
  /// pushes a one-stream target from #1 to #102.
  List<ChartRankingEvent> pushOut(Duration from) => [
    for (var index = 0; index < 101; index++)
      at(competitor(index), from + Duration(seconds: index)),
  ];

  ChartRankedEntity target(List<ChartRankedEntity> result) =>
      result.firstWhere((entry) => entry.entityId == 'target');

  const lastWeekFifth = {
    'target': ChartRankingHistory(
      entityId: 'target',
      finalizedWeeksOnChart: 6,
      hasEverCharted: true,
      previousFinalRank: 5,
      previousExtendedRank: 5,
      peakRank: 2,
    ),
  };

  test('last week #5, dips to #102 mid-week, finishes #1: up 4, not '
      'RE-ENTRY', () {
    final result = engine.rank(
      events: [
        at('target', Duration.zero),
        ...pushOut(const Duration(hours: 1)),
        at('target', const Duration(hours: 2)),
      ],
      historyByEntityId: lastWeekFifth,
    );

    final entry = target(result);
    expect(entry.rank, 1);
    expect(entry.hasReenteredOfficialChartThisWeek, isTrue);
    expect(entry.previousFinalRank, 5);
    expect(entry.movement, ChartMovement.up);
    expect(entry.previousFinalRank! - entry.rank, 4);
  });

  test('last week #5, finishes #102 after a mid-week return: down', () {
    final result = engine.rank(
      events: [
        at('target', Duration.zero),
        ...pushOut(const Duration(hours: 1)),
        at('target', const Duration(hours: 2)),
        ...pushOut(const Duration(hours: 3)),
      ],
      historyByEntityId: lastWeekFifth,
    );

    final entry = target(result);
    expect(entry.rank, 102);
    expect(entry.movement, ChartMovement.down);
  });

  test('a first week that returns mid-week but finishes in #101–200 is not '
      'RE-ENTRY', () {
    final result = engine.rank(
      events: [
        at('target', Duration.zero),
        ...pushOut(const Duration(hours: 1)),
        at('target', const Duration(hours: 2)),
        ...pushOut(const Duration(hours: 3)),
      ],
    );

    final entry = target(result);
    expect(entry.rank, 102);
    expect(entry.hasReenteredOfficialChartThisWeek, isTrue);
    expect(entry.movement, ChartMovement.newEntry);
  });

  test('an earlier chart run without last week stays RE-ENTRY', () {
    final result = engine.rank(
      events: [at('target', Duration.zero)],
      historyByEntityId: const {
        'target': ChartRankingHistory(
          entityId: 'target',
          finalizedWeeksOnChart: 2,
          hasEverCharted: true,
          previousExtendedRank: 140,
        ),
      },
    );

    expect(target(result).movement, ChartMovement.reentry);
  });

  test('E-Q7: weekly ties go to the most recent stream, lifetime ties to '
      'the incumbent', () {
    final events = [
      at('first', const Duration(hours: 1)),
      at('second', const Duration(hours: 2)),
      at('first', const Duration(hours: 3)),
      at('second', const Duration(hours: 4)),
    ];

    expect(engine.rank(events: events).map((entry) => entry.entityId), [
      'second',
      'first',
    ]);
    expect(
      const AllTimeChartRankingEngine()
          .rank(events: events, comparisonStartUtc: weekStart)
          .map((entry) => entry.entityId),
      ['first', 'second'],
    );
  });
}
