import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_rank_trend.dart';

ChartEntry _entry(String id, int rank) => ChartEntry(
  entity: ChartEntitySnapshot(entityId: id, title: id, artistName: 'A'),
  rank: rank,
  qualifiedStreamCount: 10,
  lastQualifiedAt: DateTime.utc(2026, 10, 1),
  peakRank: rank,
  peakAchievedAt: DateTime.utc(2026, 10, 1),
  weeksOnChart: 1,
  movement: ChartMovement.same,
);

ChartSnapshot _week(
  int index,
  Map<String, int> ranks, {
  bool finalized = true,
  ChartType type = ChartType.songs,
}) {
  final start = DateTime.utc(2026, 9, 6).add(Duration(days: 7 * index));
  return ChartSnapshot(
    id: 'w$index-${type.name}',
    chartType: type,
    weekStartUtc: start,
    weekEndUtc: start.add(const Duration(days: 7)),
    finalizedAt: finalized ? start.add(const Duration(days: 7)) : null,
    entries: [for (final e in ranks.entries) _entry(e.key, e.value)],
  );
}

void main() {
  test('oldest first, with a gap for a week off the chart', () {
    final trend = ChartRankTrend.of(
      [
        _week(2, {'s': 3}),
        _week(0, {'s': 9}),
        _week(1, {'other': 1}),
      ],
      chartType: ChartType.songs,
      entityId: 's',
    )!;

    expect([for (final w in trend.weeks) w.rank], [9, null, 3]);
    expect(trend.bestRank, 3);
    expect(trend.latestRank, 3);
    expect(
      trend.spokenLabel,
      'Weekly chart positions over the last 3 finalized weeks, number 9, '
      'not on the chart, number 3',
    );
  });

  test('never draws from one point, and never invents one', () {
    expect(
      ChartRankTrend.of(
        [
          _week(0, {'s': 4}),
          _week(1, {'other': 1}),
        ],
        chartType: ChartType.songs,
        entityId: 's',
      ),
      isNull,
    );
    expect(
      ChartRankTrend.of(const [], chartType: ChartType.songs, entityId: 's'),
      isNull,
    );
  });

  test('only finalized weeks of the same chart count', () {
    final trend = ChartRankTrend.of(
      [
        _week(0, {'s': 5}),
        _week(1, {'s': 2}),
        // The provisional week in progress is never part of the trend.
        _week(2, {'s': 1}, finalized: false),
        // Nor another chart's week.
        _week(3, {'s': 1}, type: ChartType.albums),
      ],
      chartType: ChartType.songs,
      entityId: 's',
    )!;

    expect([for (final w in trend.weeks) w.rank], [5, 2]);
  });

  test('keeps the most recent eight weeks, through the week shown', () {
    final history = [
      for (var i = 0; i < 12; i++) _week(i, {'s': 20 - i}),
    ];
    final latest = ChartRankTrend.of(
      history,
      chartType: ChartType.songs,
      entityId: 's',
    )!;
    expect(latest.weeks, hasLength(ChartRankTrend.maxWeeks));
    expect(latest.latestRank, 9);

    final older = ChartRankTrend.of(
      history,
      chartType: ChartType.songs,
      entityId: 's',
      throughWeekStartUtc: history[5].weekStartUtc,
    )!;
    expect(older.weeks, hasLength(6));
    expect(older.latestRank, 15);
  });
}
