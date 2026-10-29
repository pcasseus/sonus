import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_longevity.dart';

void main() {
  final first = DateTime.utc(2026, 8, 30);

  DateTime week(int index) => first.add(Duration(days: 7 * index));

  /// A finalized week; [ranks] maps entity ids to positions.
  ChartSnapshot snapshot(int index, Map<String, int> ranks) => ChartSnapshot(
    id: 'week-$index',
    chartType: ChartType.songs,
    weekStartUtc: week(index),
    weekEndUtc: week(index + 1),
    finalizedAt: week(index + 1),
    entries: [
      for (final MapEntry(key: id, value: rank) in ranks.entries)
        ChartEntry(
          entity: ChartEntitySnapshot(
            entityId: id,
            title: id,
            artistName: 'Artist',
          ),
          rank: rank,
          qualifiedStreamCount: 10,
          lastQualifiedAt: week(index),
          peakRank: rank,
          peakAchievedAt: week(index),
          weeksOnChart: 1,
          movement: ChartMovement.newEntry,
        ),
    ],
  );

  test('counts weeks at #1, the longest run and the Top 10 streak', () {
    // Newest first, as history is read.
    final index = ChartLongevityIndex.fromHistory([
      snapshot(5, {'a': 4}),
      snapshot(4, {'a': 1}),
      snapshot(3, {'a': 1}),
      snapshot(2, {'a': 1}),
      snapshot(1, {'a': 12}),
      snapshot(0, {'a': 1}),
    ]);

    final latest = index.latest('a')!;
    expect(latest.weeksAtNumberOne, 4);
    expect(latest.longestNumberOneRun, 3);
    expect(latest.topTenStreak, 4);
    expect(latest.officialWeeks, 6);
    expect(latest.debutWeekStartUtc, week(0));
    expect(latest.debutRank, 1);
  });

  test('a week without the entity in the Top 10 ends the streak', () {
    final index = ChartLongevityIndex.fromHistory([
      snapshot(2, {'a': 30, 'b': 2}),
      snapshot(1, {'a': 3, 'b': 2}),
      snapshot(0, {'a': 2}),
    ]);

    expect(index.latest('a')!.topTenStreak, 0);
    expect(index.latest('b')!.topTenStreak, 2);
    expect(index.latest('b')!.debutRank, 2);
    expect(index.latest('b')!.debutWeekStartUtc, week(1));
  });

  test('a missing week breaks runs; weeks must follow each other', () {
    final index = ChartLongevityIndex.fromHistory([
      snapshot(3, {'a': 1}),
      snapshot(1, {'a': 1}),
      snapshot(0, {'a': 1}),
    ]);

    final latest = index.latest('a')!;
    expect(latest.weeksAtNumberOne, 3);
    expect(latest.longestNumberOneRun, 2);
    expect(latest.topTenStreak, 1);
  });

  test('stats as of an older week ignore later weeks', () {
    final index = ChartLongevityIndex.fromHistory([
      snapshot(2, {'a': 1}),
      snapshot(1, {'a': 1}),
      snapshot(0, {'a': 5}),
    ]);

    final asOf = index.asOfWeek(week(1), 'a')!;
    expect(asOf.weeksAtNumberOne, 1);
    expect(asOf.topTenStreak, 2);
    expect(asOf.officialWeeks, 2);
    expect(index.latest('a')!.weeksAtNumberOne, 2);
  });

  test('Bubbling Under weeks are not official and never a debut', () {
    final index = ChartLongevityIndex.fromHistory([
      snapshot(1, {'a': 90}),
      snapshot(0, {'a': 150, 'b': 120}),
    ]);

    expect(index.latest('a')!.officialWeeks, 1);
    expect(index.latest('a')!.debutRank, 90);
    expect(index.latest('a')!.debutWeekStartUtc, week(1));
    expect(index.latest('b'), isNull);
    expect(index.asOfWeek(week(0), 'b'), isNull);
  });

  test('last week in #101–200 is context for the following week only', () {
    final index = ChartLongevityIndex.fromHistory([
      snapshot(3, {'a': 70}),
      snapshot(1, {'a': 80}),
      snapshot(0, {'a': 150, 'b': 5}),
    ]);

    expect(index.previousExtendedRank(week(1), 'a'), 150);
    expect(index.previousExtendedRank(week(1), 'b'), isNull);
    // Week 2 is missing, so week 3 has no "last week" to look at.
    expect(index.previousExtendedRank(week(3), 'a'), isNull);
  });

  test('the history is read, never changed', () {
    final history = [
      snapshot(1, {'a': 1}),
      snapshot(0, {'a': 2}),
    ];
    final before = [for (final week in history) week.id];

    ChartLongevityIndex.fromHistory(history);

    expect([for (final week in history) week.id], before);
    expect(history.first.entries.single.rank, 1);
  });
}
