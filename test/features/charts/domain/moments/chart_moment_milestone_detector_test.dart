import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_longevity_state.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_milestone_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentMilestoneDetector();

  const entity = ChartEntitySnapshot(
    entityId: 'song-a',
    title: 'Song A',
    artistName: 'Artist A',
    albumTitle: 'Album A',
  );

  ChartEntry entry({
    int rank = 5,
    int? previousFinalRank = 8,
    int qualifiedStreamCount = 30,
  }) {
    return ChartEntry(
      entity: entity,
      rank: rank,
      previousFinalRank: previousFinalRank,
      qualifiedStreamCount: qualifiedStreamCount,
      lastQualifiedAt: DateTime.utc(2026, 10, 3, 20),
      peakRank: rank,
      peakAchievedAt: DateTime.utc(2026, 10, 3, 20),
      weeksOnChart: 5,
      movement: ChartMovement.up,
    );
  }

  ChartSnapshot snapshot({
    ChartType chartType = ChartType.songs,
    bool finalized = true,
  }) {
    return ChartSnapshot(
      id: 'chart-${chartType.name}-2026-09-27',
      chartType: chartType,
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
      finalizedAt: finalized ? DateTime.utc(2026, 10, 4) : null,
      entries: [entry()],
    );
  }

  ChartMomentLongevityState longevity({
    int total = 0,
    int consecutive = 0,
    Map<int, int> totalThreshold = const {},
    Map<int, int> consecutiveThreshold = const {},
  }) {
    return ChartMomentLongevityState(
      totalChartWeeks: total,
      consecutiveChartWeeks: consecutive,
      totalThresholdWeeks: totalThreshold,
      consecutiveThresholdWeeks: consecutiveThreshold,
    );
  }

  group('ChartMomentMilestoneDetector', () {
    test('emits newly crossed total and consecutive week milestones', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(total: 4, consecutive: 4),
        currentLongevity: longevity(total: 5, consecutive: 5),
        previousLifetimeStreams: 24,
        currentLifetimeStreams: 24,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(events, hasLength(2));

      expect(events.map((event) => event.eventType).toSet(), {
        ChartMomentEventType.totalWeeksMilestone,
        ChartMomentEventType.consecutiveWeeksMilestone,
      });

      expect(events.every((event) => event.milestoneValue == 5), isTrue);

      expect(
        events.every((event) => event.scope == ChartMomentScope.finalized),
        isTrue,
      );
    });

    test('does not repeat week milestone already reached previously', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(total: 5, consecutive: 5),
        currentLongevity: longevity(total: 6, consecutive: 6),
        previousLifetimeStreams: 0,
        currentLifetimeStreams: 0,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(events, isEmpty);
    });

    test('emits total and consecutive threshold-week milestones', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(rank: 8),
        previousLongevity: longevity(
          totalThreshold: const {10: 4},
          consecutiveThreshold: const {10: 4},
        ),
        currentLongevity: longevity(
          totalThreshold: const {10: 5},
          consecutiveThreshold: const {10: 5},
        ),
        previousLifetimeStreams: 0,
        currentLifetimeStreams: 0,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(events, hasLength(2));

      final total = events.singleWhere(
        (event) =>
            event.eventType ==
            ChartMomentEventType.totalThresholdWeeksMilestone,
      );

      final consecutive = events.singleWhere(
        (event) =>
            event.eventType ==
            ChartMomentEventType.consecutiveThresholdWeeksMilestone,
      );

      expect(total.threshold, 10);
      expect(total.milestoneValue, 5);

      expect(consecutive.threshold, 10);
      expect(consecutive.milestoneValue, 5);
    });

    test('threshold milestone streams are independent by threshold', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(rank: 5),
        previousLongevity: longevity(totalThreshold: const {10: 4, 5: 1}),
        currentLongevity: longevity(totalThreshold: const {10: 5, 5: 2}),
        previousLifetimeStreams: 0,
        currentLifetimeStreams: 0,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      final totals = events
          .where(
            (event) =>
                event.eventType ==
                ChartMomentEventType.totalThresholdWeeksMilestone,
          )
          .toList();

      expect(totals, hasLength(2));

      expect(
        totals
            .map((event) => '${event.threshold}:${event.milestoneValue}')
            .toSet(),
        {'10:5', '5:2'},
      );
    });

    test('emits every lifetime stream milestone crossed in the week', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(),
        currentLongevity: longevity(),
        previousLifetimeStreams: 40,
        currentLifetimeStreams: 110,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      final streamEvents = events
          .where(
            (event) =>
                event.eventType == ChartMomentEventType.lifetimeStreamMilestone,
          )
          .toList();

      expect(streamEvents.map((event) => event.milestoneValue).toList(), [
        50,
        100,
      ]);
    });

    test('does not emit a stream milestone before it is reached', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(),
        currentLongevity: longevity(),
        previousLifetimeStreams: 24,
        currentLifetimeStreams: 24,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(events, isEmpty);
    });

    test('first milestone is emitted from zero state', () {
      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(),
        currentLongevity: longevity(total: 1, consecutive: 1),
        previousLifetimeStreams: 0,
        currentLifetimeStreams: 10,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(
        events
            .where(
              (event) =>
                  event.eventType == ChartMomentEventType.totalWeeksMilestone,
            )
            .single
            .milestoneValue,
        1,
      );

      expect(
        events
            .where(
              (event) =>
                  event.eventType ==
                  ChartMomentEventType.consecutiveWeeksMilestone,
            )
            .single
            .milestoneValue,
        1,
      );

      expect(
        events
            .where(
              (event) =>
                  event.eventType ==
                  ChartMomentEventType.lifetimeStreamMilestone,
            )
            .single
            .milestoneValue,
        10,
      );
    });

    test('rebuild produces stable milestone ids and dedupe keys', () {
      List<String> buildIds() {
        return detector
            .detect(
              snapshot: snapshot(),
              entry: entry(),
              previousLongevity: longevity(total: 4),
              currentLongevity: longevity(total: 5),
              previousLifetimeStreams: 40,
              currentLifetimeStreams: 50,
              createdAt: DateTime.utc(2026, 10, 4, 1),
            )
            .map((event) => event.id)
            .toList();
      }

      final first = buildIds();
      final second = buildIds();

      expect(first, second);

      final events = detector.detect(
        snapshot: snapshot(),
        entry: entry(),
        previousLongevity: longevity(total: 4),
        currentLongevity: longevity(total: 5),
        previousLifetimeStreams: 40,
        currentLifetimeStreams: 50,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(
        events.every((event) => event.id == event.deduplicationKey),
        isTrue,
      );
    });

    test('supports album milestone events with identical semantics', () {
      final albumSnapshot = snapshot(chartType: ChartType.albums);

      final events = detector.detect(
        snapshot: albumSnapshot,
        entry: entry(),
        previousLongevity: longevity(total: 1),
        currentLongevity: longevity(total: 2),
        previousLifetimeStreams: 24,
        currentLifetimeStreams: 25,
        createdAt: DateTime.utc(2026, 10, 4, 1),
      );

      expect(events, hasLength(2));

      expect(
        events.every((event) => event.chartType == ChartType.albums),
        isTrue,
      );

      expect(events.map((event) => event.eventType).toSet(), {
        ChartMomentEventType.totalWeeksMilestone,
        ChartMomentEventType.lifetimeStreamMilestone,
      });
    });

    test('rejects live snapshot', () {
      expect(
        () => detector.detect(
          snapshot: snapshot(finalized: false),
          entry: entry(),
          previousLongevity: longevity(),
          currentLongevity: longevity(),
          previousLifetimeStreams: 0,
          currentLifetimeStreams: 0,
          createdAt: DateTime.utc(2026, 10, 4, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative lifetime stream state', () {
      expect(
        () => detector.detect(
          snapshot: snapshot(),
          entry: entry(),
          previousLongevity: longevity(),
          currentLongevity: longevity(),
          previousLifetimeStreams: -1,
          currentLifetimeStreams: 0,
          createdAt: DateTime.utc(2026, 10, 4, 1),
        ),
        throwsArgumentError,
      );

      expect(
        () => detector.detect(
          snapshot: snapshot(),
          entry: entry(),
          previousLongevity: longevity(),
          currentLongevity: longevity(),
          previousLifetimeStreams: 0,
          currentLifetimeStreams: -1,
          createdAt: DateTime.utc(2026, 10, 4, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
