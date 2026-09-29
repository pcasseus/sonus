import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_longevity_calculator.dart';

void main() {
  const calculator = ChartMomentLongevityCalculator();

  const entity = ChartEntitySnapshot(
    entityId: 'song-a',
    title: 'Song A',
    artistName: 'Artist A',
    albumTitle: 'Album A',
  );

  ChartEntry entry(int rank) {
    return ChartEntry(
      entity: entity,
      rank: rank,
      qualifiedStreamCount: 10,
      lastQualifiedAt: DateTime.utc(2026, 10, 3),
      peakRank: rank,
      peakAchievedAt: DateTime.utc(2026, 10, 3),
      weeksOnChart: 1,
      movement: ChartMovement.newEntry,
    );
  }

  ChartSnapshot week(
    DateTime start, {
    int? rank,
    ChartType chartType = ChartType.songs,
  }) {
    return ChartSnapshot(
      id: '${chartType.name}-${start.toIso8601String()}',
      chartType: chartType,
      weekStartUtc: start,
      weekEndUtc: start.add(const Duration(days: 7)),
      finalizedAt: start.add(const Duration(days: 7)),
      entries: rank == null ? const [] : [entry(rank)],
    );
  }

  group('ChartMomentLongevityCalculator', () {
    test('counts first finalized appearance', () {
      final current = week(DateTime.utc(2026, 9, 27), rank: 8);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: const [],
      );

      expect(state.totalChartWeeks, 1);
      expect(state.consecutiveChartWeeks, 1);

      expect(state.totalWeeksAt(10), 1);
      expect(state.consecutiveWeeksAt(10), 1);

      expect(state.totalWeeksAt(5), 0);
      expect(state.consecutiveWeeksAt(5), 0);
    });

    test('counts consecutive finalized chart weeks', () {
      final first = week(DateTime.utc(2026, 9, 13), rank: 20);

      final second = week(DateTime.utc(2026, 9, 20), rank: 15);

      final current = week(DateTime.utc(2026, 9, 27), rank: 10);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [first, second],
      );

      expect(state.totalChartWeeks, 3);
      expect(state.consecutiveChartWeeks, 3);

      expect(state.totalWeeksAt(20), 3);
      expect(state.consecutiveWeeksAt(20), 3);

      expect(state.totalWeeksAt(10), 1);
      expect(state.consecutiveWeeksAt(10), 1);
    });

    test('gap breaks chart streak without resetting lifetime total', () {
      final old = week(DateTime.utc(2026, 9, 6), rank: 30);

      final gap = week(DateTime.utc(2026, 9, 13));

      final previous = week(DateTime.utc(2026, 9, 20), rank: 25);

      final current = week(DateTime.utc(2026, 9, 27), rank: 20);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [old, gap, previous],
      );

      expect(state.totalChartWeeks, 3);
      expect(state.consecutiveChartWeeks, 2);
    });

    test('threshold streak breaks independently from chart streak', () {
      final first = week(DateTime.utc(2026, 9, 13), rank: 9);

      final second = week(DateTime.utc(2026, 9, 20), rank: 14);

      final current = week(DateTime.utc(2026, 9, 27), rank: 8);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [first, second],
      );

      expect(state.totalChartWeeks, 3);
      expect(state.consecutiveChartWeeks, 3);

      expect(state.totalWeeksAt(10), 2);
      expect(state.consecutiveWeeksAt(10), 1);

      expect(state.totalWeeksAt(15), 3);
      expect(state.consecutiveWeeksAt(15), 3);
    });

    test('current entity outside a threshold has zero current streak', () {
      final previous = week(DateTime.utc(2026, 9, 20), rank: 5);

      final current = week(DateTime.utc(2026, 9, 27), rank: 12);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [previous],
      );

      expect(state.totalWeeksAt(5), 1);
      expect(state.consecutiveWeeksAt(5), 0);

      expect(state.totalChartWeeks, 2);
      expect(state.consecutiveChartWeeks, 2);
    });

    test('historical same-week revision is excluded', () {
      final previous = week(DateTime.utc(2026, 9, 20), rank: 20);

      final staleCurrent = week(DateTime.utc(2026, 9, 27), rank: 1);

      final current = week(DateTime.utc(2026, 9, 27), rank: 10);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [previous, staleCurrent],
      );

      expect(state.totalChartWeeks, 2);
      expect(state.totalWeeksAt(1), 0);
      expect(state.totalWeeksAt(10), 1);
    });

    test('future finalized history is excluded', () {
      final current = week(DateTime.utc(2026, 9, 27), rank: 10);

      final future = week(DateTime.utc(2026, 10, 4), rank: 1);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [future],
      );

      expect(state.totalChartWeeks, 1);
      expect(state.totalWeeksAt(1), 0);
    });

    test('other chart type history is ignored', () {
      final oldAlbum = week(
        DateTime.utc(2026, 9, 20),
        rank: 1,
        chartType: ChartType.albums,
      );

      final current = week(DateTime.utc(2026, 9, 27), rank: 10);

      final state = calculator.calculate(
        entityId: 'song-a',
        snapshot: current,
        history: [oldAlbum],
      );

      expect(state.totalChartWeeks, 1);
      expect(state.totalWeeksAt(1), 0);
    });

    test('rejects live current snapshot', () {
      final start = DateTime.utc(2026, 9, 27);

      final live = ChartSnapshot(
        id: 'live',
        chartType: ChartType.songs,
        weekStartUtc: start,
        weekEndUtc: start.add(const Duration(days: 7)),
        entries: [entry(10)],
      );

      expect(
        () => calculator.calculate(
          entityId: 'song-a',
          snapshot: live,
          history: const [],
        ),
        throwsArgumentError,
      );
    });
  });
}
