import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_finalized_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentFinalizedDetector();

  final currentStart = DateTime.utc(2026, 9, 27);
  final currentEnd = DateTime.utc(2026, 10, 4);
  final createdAt = DateTime.utc(2026, 10, 4, 1);

  const song = ChartEntitySnapshot(
    entityId: 'song-a',
    title: 'Song A',
    artistName: 'Artist A',
    albumTitle: 'Album A',
  );

  ChartEntry entry({
    ChartEntitySnapshot entity = song,
    required int rank,
    required int peakRank,
    int streams = 10,
    int weeksOnChart = 1,
    int? previousFinalRank,
    ChartMovement movement = ChartMovement.newEntry,
  }) {
    return ChartEntry(
      entity: entity,
      rank: rank,
      qualifiedStreamCount: streams,
      lastQualifiedAt: DateTime.utc(2026, 10, 3, 20),
      previousFinalRank: previousFinalRank,
      peakRank: peakRank,
      peakAchievedAt: DateTime.utc(2026, 10, 3, 20),
      weeksOnChart: weeksOnChart,
      movement: movement,
    );
  }

  ChartSnapshot finalized({
    required String id,
    required DateTime start,
    required DateTime end,
    required List<ChartEntry> entries,
    ChartType chartType = ChartType.songs,
  }) {
    return ChartSnapshot(
      id: id,
      chartType: chartType,
      weekStartUtc: start,
      weekEndUtc: end,
      finalizedAt: end,
      entries: entries,
    );
  }

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    Iterable<ChartSnapshot> history = const [],
  }) {
    return detector.detect(
      snapshot: snapshot,
      history: history,
      createdAt: createdAt,
    );
  }

  List<ChartMomentEvent> ofType(
    List<ChartMomentEvent> events,
    ChartMomentEventType type,
  ) {
    return events
        .where((event) => event.eventType == type)
        .toList(growable: false);
  }

  group('ChartMomentFinalizedDetector', () {
    test('rejects live snapshots', () {
      final live = ChartSnapshot(
        id: 'live',
        chartType: ChartType.songs,
        weekStartUtc: currentStart,
        weekEndUtc: currentEnd,
        entries: [entry(rank: 3, peakRank: 3)],
      );

      expect(() => detect(snapshot: live), throwsArgumentError);
    });

    test('first finalized appearance emits debut threshold and peak facts', () {
      final snapshot = finalized(
        id: 'chart_songs_current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(rank: 3, peakRank: 3)],
      );

      final events = detect(snapshot: snapshot);

      expect(ofType(events, ChartMomentEventType.debut), hasLength(1));

      expect(
        ofType(
          events,
          ChartMomentEventType.firstThresholdEntry,
        ).map((event) => event.threshold).toList(),
        [200, 100, 75, 50, 40, 30, 25, 20, 15, 10, 5, 3],
      );

      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));

      expect(
        events.every((event) => event.scope == ChartMomentScope.finalized),
        isTrue,
      );

      expect(
        events.every((event) => event.sourceId == 'chart_songs_current'),
        isTrue,
      );

      expect(events.every((event) => event.occurredAt == currentEnd), isTrue);
    });

    test('weekly continuation emits finalized rise and crossed thresholds', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 15, peakRank: 15, previousFinalRank: null)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 3,
            peakRank: 3,
            previousFinalRank: 15,
            movement: ChartMovement.up,
            weeksOnChart: 2,
          ),
        ],
      );

      final events = detect(snapshot: snapshot, history: [previous]);

      final rise = ofType(events, ChartMomentEventType.rankRise).single;

      expect(rise.previousRank, 15);
      expect(rise.currentRank, 3);

      expect(
        ofType(
          events,
          ChartMomentEventType.firstThresholdEntry,
        ).map((event) => event.threshold).toList(),
        [10, 5, 3],
      );

      final peak = ofType(events, ChartMomentEventType.newPeak).single;
      expect(peak.previousPeakRank, 15);
      expect(peak.currentPeakRank, 3);
    });

    test('historical absence produces reentry and threshold returns', () {
      final old = finalized(
        id: 'old',
        start: DateTime.utc(2026, 9, 6),
        end: DateTime.utc(2026, 9, 13),
        entries: [entry(rank: 5, peakRank: 5)],
      );

      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: const [],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [entry(rank: 3, peakRank: 3)],
      );

      final events = detect(snapshot: snapshot, history: [old, previous]);

      expect(ofType(events, ChartMomentEventType.reentry), hasLength(1));

      expect(
        ofType(
          events,
          ChartMomentEventType.thresholdReturn,
        ).map((event) => event.threshold).toList(),
        [200, 100, 75, 50, 40, 30, 25, 20, 15, 10, 5],
      );

      expect(
        ofType(
          events,
          ChartMomentEventType.firstThresholdEntry,
        ).map((event) => event.threshold).toList(),
        [3],
      );

      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));
    });

    test(
      'entity missing from current week emits chart and threshold exits',
      () {
        final previous = finalized(
          id: 'previous',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          entries: [entry(rank: 10, peakRank: 5)],
        );

        final snapshot = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: const [],
        );

        final events = detect(snapshot: snapshot, history: [previous]);

        expect(ofType(events, ChartMomentEventType.chartExit), hasLength(1));

        expect(
          ofType(
            events,
            ChartMomentEventType.thresholdExit,
          ).map((event) => event.threshold).toList(),
          [200, 100, 75, 50, 40, 30, 25, 20, 15, 10],
        );
      },
    );

    test('first finalized number one emits number-one accomplishment', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 2, peakRank: 2)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 1,
            peakRank: 1,
            previousFinalRank: 2,
            movement: ChartMovement.up,
          ),
        ],
      );

      final events = detect(snapshot: snapshot, history: [previous]);

      expect(ofType(events, ChartMomentEventType.rankRise), hasLength(1));

      expect(ofType(events, ChartMomentEventType.firstNumberOne), hasLength(1));

      expect(ofType(events, ChartMomentEventType.returnToNumberOne), isEmpty);

      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));
    });

    test(
      'return to finalized number one is distinct from first number one',
      () {
        final old = finalized(
          id: 'old',
          start: DateTime.utc(2026, 9, 13),
          end: DateTime.utc(2026, 9, 20),
          entries: [entry(rank: 1, peakRank: 1)],
        );

        final previous = finalized(
          id: 'previous',
          start: DateTime.utc(2026, 9, 20),
          end: currentStart,
          entries: [
            entry(
              rank: 2,
              peakRank: 1,
              previousFinalRank: 1,
              movement: ChartMovement.down,
            ),
          ],
        );

        final snapshot = finalized(
          id: 'current',
          start: currentStart,
          end: currentEnd,
          entries: [
            entry(
              rank: 1,
              peakRank: 1,
              previousFinalRank: 2,
              movement: ChartMovement.up,
            ),
          ],
        );

        final events = detect(snapshot: snapshot, history: [old, previous]);

        expect(ofType(events, ChartMomentEventType.firstNumberOne), isEmpty);

        expect(
          ofType(events, ChartMomentEventType.returnToNumberOne),
          hasLength(1),
        );

        expect(
          ofType(
            events,
            ChartMomentEventType.thresholdReturn,
          ).where((event) => event.threshold == 1),
          hasLength(1),
        );

        expect(ofType(events, ChartMomentEventType.peakMatch), hasLength(1));
      },
    );

    test('falling from finalized number one records official loss', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 1, peakRank: 1)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 2,
            peakRank: 1,
            previousFinalRank: 1,
            movement: ChartMovement.down,
          ),
        ],
      );

      final events = detect(snapshot: snapshot, history: [previous]);

      expect(ofType(events, ChartMomentEventType.rankFall), hasLength(1));
      expect(ofType(events, ChartMomentEventType.losesNumberOne), hasLength(1));

      expect(
        ofType(
          events,
          ChartMomentEventType.thresholdExit,
        ).where((event) => event.threshold == 1),
        hasLength(1),
      );
    });

    test('unchanged finalized rank records rankSame', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 11, peakRank: 7)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 11,
            peakRank: 7,
            previousFinalRank: 11,
            movement: ChartMovement.same,
          ),
        ],
      );

      final events = detect(snapshot: snapshot, history: [previous]);

      expect(ofType(events, ChartMomentEventType.rankSame), hasLength(1));
      expect(ofType(events, ChartMomentEventType.rankRise), isEmpty);
      expect(ofType(events, ChartMomentEventType.rankFall), isEmpty);
    });

    test('same-week stale revision and future history are ignored', () {
      final older = finalized(
        id: 'older',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 8, peakRank: 8)],
      );

      final staleSameWeek = finalized(
        id: 'stale-current-revision',
        start: currentStart,
        end: currentEnd,
        entries: [entry(rank: 1, peakRank: 1)],
      );

      final future = finalized(
        id: 'future',
        start: currentEnd,
        end: DateTime.utc(2026, 10, 11),
        entries: [entry(rank: 1, peakRank: 1)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 3,
            peakRank: 3,
            previousFinalRank: 8,
            movement: ChartMovement.up,
          ),
        ],
      );

      final events = detect(
        snapshot: snapshot,
        history: [older, staleSameWeek, future],
      );

      final peak = ofType(events, ChartMomentEventType.newPeak).single;

      expect(peak.previousPeakRank, 8);
      expect(peak.currentPeakRank, 3);

      expect(ofType(events, ChartMomentEventType.peakMatch), isEmpty);
    });

    test('rebuilding finalized facts produces stable identities', () {
      final previous = finalized(
        id: 'previous',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        entries: [entry(rank: 15, peakRank: 15)],
      );

      final snapshot = finalized(
        id: 'current',
        start: currentStart,
        end: currentEnd,
        entries: [
          entry(
            rank: 3,
            peakRank: 3,
            previousFinalRank: 15,
            movement: ChartMovement.up,
          ),
        ],
      );

      final first = detector.detect(
        snapshot: snapshot,
        history: [previous],
        createdAt: createdAt,
      );

      final rebuilt = detector.detect(
        snapshot: snapshot,
        history: [previous],
        createdAt: createdAt.add(const Duration(hours: 4)),
      );

      expect(
        first.map((event) => event.id).toList(),
        rebuilt.map((event) => event.id).toList(),
      );

      expect(
        first.map((event) => event.deduplicationKey).toList(),
        rebuilt.map((event) => event.deduplicationKey).toList(),
      );

      expect(
        first.map((event) => event.deduplicationKey).toSet().length,
        first.length,
      );
    });

    test('albums use the same finalized fact semantics', () {
      const album = ChartEntitySnapshot(
        entityId: 'album-a',
        title: 'Album A',
        artistName: 'Artist A',
      );

      final previous = finalized(
        id: 'previous-albums',
        start: DateTime.utc(2026, 9, 20),
        end: currentStart,
        chartType: ChartType.albums,
        entries: [entry(entity: album, rank: 25, peakRank: 25)],
      );

      final snapshot = finalized(
        id: 'current-albums',
        start: currentStart,
        end: currentEnd,
        chartType: ChartType.albums,
        entries: [
          entry(
            entity: album,
            rank: 20,
            peakRank: 20,
            previousFinalRank: 25,
            movement: ChartMovement.up,
          ),
        ],
      );

      final events = detect(snapshot: snapshot, history: [previous]);

      expect(events.first.chartType, ChartType.albums);
      expect(ofType(events, ChartMomentEventType.rankRise), hasLength(1));

      expect(
        ofType(
          events,
          ChartMomentEventType.firstThresholdEntry,
        ).map((event) => event.threshold).toList(),
        [20],
      );

      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));
    });
  });
}
