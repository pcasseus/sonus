import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_live_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rank_observation.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentLiveDetector();

  const entity = ChartEntitySnapshot(
    entityId: 'song_a',
    title: 'Song A',
    artistName: 'Artist A',
    albumTitle: 'Album A',
  );

  final weekStart = DateTime.utc(2026, 9, 27);
  final weekEnd = DateTime.utc(2026, 10, 4);
  final createdAt = DateTime.utc(2026, 9, 29, 15);

  ChartMomentRankObservation observation({
    required String sourceEventId,
    required int? previousRank,
    required int? currentRank,
    bool hadPreviousObservation = true,
    int? previousPeakRank,
    int? currentPeakRank,
    int? previousFinalizedRank,
    int minute = 0,
  }) {
    return ChartMomentRankObservation(
      sourceEventId: sourceEventId,
      entityId: entity.entityId,
      hadPreviousObservation: hadPreviousObservation,
      previousRank: previousRank,
      currentRank: currentRank,
      previousPeakRank: previousPeakRank,
      currentPeakRank: currentPeakRank,
      previousFinalizedRank: previousFinalizedRank,
      observedAt: DateTime.utc(2026, 9, 29, 14, minute),
    );
  }

  List<ChartMomentEvent> detect(ChartMomentRankObservation observation) {
    return detector.detectRankTransition(
      chartType: ChartType.songs,
      entity: entity,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      observation: observation,
      createdAt: createdAt,
      qualifiedStreamCount: 8,
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

  group('ChartMomentLiveDetector', () {
    test('detects an ordinary one-position rise', () {
      final events = detect(
        observation(
          sourceEventId: 'play_1',
          previousRank: 18,
          currentRank: 17,
          previousPeakRank: 10,
          currentPeakRank: 10,
        ),
      );

      expect(events, hasLength(1));

      final event = events.single;

      expect(event.scope, ChartMomentScope.live);
      expect(event.eventType, ChartMomentEventType.rankRise);
      expect(event.previousRank, 18);
      expect(event.currentRank, 17);
      expect(event.movementDistance, 1);
      expect(event.qualifiedStreamCount, 8);
      expect(event.sourceId, 'play_1');
    });

    test('one transition emits every crossed threshold and a new peak', () {
      final events = detect(
        observation(
          sourceEventId: 'play_multi',
          previousRank: 15,
          currentRank: 3,
          previousPeakRank: 15,
          currentPeakRank: 3,
        ),
      );

      expect(events.map((event) => event.eventType).toList(), [
        ChartMomentEventType.rankRise,
        ChartMomentEventType.firstThresholdEntry,
        ChartMomentEventType.firstThresholdEntry,
        ChartMomentEventType.firstThresholdEntry,
        ChartMomentEventType.newPeak,
      ]);

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

    test('threshold history distinguishes returns from first entries', () {
      final events = detect(
        observation(
          sourceEventId: 'play_history',
          previousRank: 15,
          currentRank: 3,
          previousPeakRank: 5,
          currentPeakRank: 3,
        ),
      );

      expect(
        ofType(
          events,
          ChartMomentEventType.thresholdReturn,
        ).map((event) => event.threshold).toList(),
        [10, 5],
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

    test('falling from number one records loss and threshold exit', () {
      final events = detect(
        observation(
          sourceEventId: 'play_fall',
          previousRank: 1,
          currentRank: 2,
          previousPeakRank: 1,
          currentPeakRank: 1,
        ),
      );

      expect(
        events.map((event) => event.eventType),
        containsAll([
          ChartMomentEventType.rankFall,
          ChartMomentEventType.thresholdExit,
          ChartMomentEventType.losesNumberOne,
        ]),
      );

      expect(
        ofType(
          events,
          ChartMomentEventType.thresholdExit,
        ).map((event) => event.threshold).toList(),
        [1],
      );
    });

    test('Top-200 exit emits lifecycle and threshold exit facts', () {
      final events = detect(
        observation(
          sourceEventId: 'play_exit',
          previousRank: 200,
          currentRank: null,
          previousPeakRank: 80,
          currentPeakRank: 80,
        ),
      );

      expect(events.map((event) => event.eventType).toList(), [
        ChartMomentEventType.chartExit,
        ChartMomentEventType.thresholdExit,
      ]);

      expect(events.last.threshold, 200);
    });

    test('return from outside Top 200 is a reentry and threshold return', () {
      final events = detect(
        observation(
          sourceEventId: 'play_reentry',
          previousRank: null,
          currentRank: 200,
          previousPeakRank: 150,
          currentPeakRank: 150,
        ),
      );

      expect(events.first.eventType, ChartMomentEventType.reentry);

      final thresholdReturn = ofType(
        events,
        ChartMomentEventType.thresholdReturn,
      ).single;

      expect(thresholdReturn.threshold, 200);
    });

    test('first observation continues prior finalized Top-200 run', () {
      final events = detect(
        observation(
          sourceEventId: 'play_continuation',
          hadPreviousObservation: false,
          previousRank: null,
          currentRank: 120,
          previousPeakRank: 143,
          currentPeakRank: 120,
          previousFinalizedRank: 143,
        ),
      );

      expect(ofType(events, ChartMomentEventType.debut), isEmpty);
      expect(ofType(events, ChartMomentEventType.reentry), isEmpty);
      expect(ofType(events, ChartMomentEventType.thresholdReturn), isEmpty);
      expect(ofType(events, ChartMomentEventType.firstThresholdEntry), isEmpty);

      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));
    });

    test('first observation after a historical absence is reentry', () {
      final events = detect(
        observation(
          sourceEventId: 'play_old_history',
          hadPreviousObservation: false,
          previousRank: null,
          currentRank: 120,
          previousPeakRank: 80,
          currentPeakRank: 80,
          previousFinalizedRank: null,
        ),
      );

      expect(ofType(events, ChartMomentEventType.reentry), hasLength(1));

      final thresholdReturn = ofType(
        events,
        ChartMomentEventType.thresholdReturn,
      ).single;

      expect(thresholdReturn.threshold, 200);
    });

    test('true first observation creates debut and first threshold facts', () {
      final events = detect(
        observation(
          sourceEventId: 'play_debut',
          hadPreviousObservation: false,
          previousRank: null,
          currentRank: 120,
          previousPeakRank: null,
          currentPeakRank: 120,
          previousFinalizedRank: null,
        ),
      );

      expect(ofType(events, ChartMomentEventType.debut), hasLength(1));

      final firstThreshold = ofType(
        events,
        ChartMomentEventType.firstThresholdEntry,
      ).single;

      expect(firstThreshold.threshold, 200);
      expect(ofType(events, ChartMomentEventType.newPeak), hasLength(1));
    });

    test(
      'first arrival at number one emits both threshold and number-one facts',
      () {
        final events = detect(
          observation(
            sourceEventId: 'play_number_one',
            previousRank: 2,
            currentRank: 1,
            previousPeakRank: 2,
            currentPeakRank: 1,
          ),
        );

        expect(
          events.map((event) => event.eventType),
          containsAll([
            ChartMomentEventType.rankRise,
            ChartMomentEventType.firstThresholdEntry,
            ChartMomentEventType.firstNumberOne,
            ChartMomentEventType.newPeak,
          ]),
        );

        expect(
          ofType(
            events,
            ChartMomentEventType.firstThresholdEntry,
          ).single.threshold,
          1,
        );
      },
    );

    test('return to number one is distinct from first number one', () {
      final events = detect(
        observation(
          sourceEventId: 'play_return_one',
          previousRank: 2,
          currentRank: 1,
          previousPeakRank: 1,
          currentPeakRank: 1,
        ),
      );

      expect(ofType(events, ChartMomentEventType.firstNumberOne), isEmpty);
      expect(
        ofType(events, ChartMomentEventType.returnToNumberOne),
        hasLength(1),
      );
      expect(
        ofType(events, ChartMomentEventType.thresholdReturn).single.threshold,
        1,
      );
      expect(ofType(events, ChartMomentEventType.peakMatch), hasLength(1));
    });

    test('unchanged rank does not create movement or repeated facts', () {
      final events = detect(
        observation(
          sourceEventId: 'play_same_rank',
          previousRank: 11,
          currentRank: 11,
          previousPeakRank: 7,
          currentPeakRank: 7,
        ),
      );

      expect(events, isEmpty);
    });

    test('rebuilding a transition produces identical fact identities', () {
      final first = detector.detectRankTransition(
        chartType: ChartType.songs,
        entity: entity,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        observation: observation(
          sourceEventId: 'play_same',
          previousRank: 15,
          currentRank: 3,
          previousPeakRank: 15,
          currentPeakRank: 3,
        ),
        createdAt: createdAt,
      );

      final rebuilt = detector.detectRankTransition(
        chartType: ChartType.songs,
        entity: entity,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        observation: observation(
          sourceEventId: 'play_same',
          previousRank: 15,
          currentRank: 3,
          previousPeakRank: 15,
          currentPeakRank: 3,
        ),
        createdAt: createdAt.add(const Duration(hours: 2)),
      );

      expect(
        first.map((event) => event.deduplicationKey).toList(),
        rebuilt.map((event) => event.deduplicationKey).toList(),
      );

      expect(
        first.map((event) => event.id).toList(),
        rebuilt.map((event) => event.id).toList(),
      );

      expect(
        first.map((event) => event.deduplicationKey).toSet().length,
        first.length,
      );
    });

    test('a legitimate reversal receives different movement identity', () {
      final rise = detect(
        observation(
          sourceEventId: 'play_6',
          previousRank: 14,
          currentRank: 13,
          previousPeakRank: 10,
          currentPeakRank: 10,
          minute: 1,
        ),
      ).single;

      final fall = detect(
        observation(
          sourceEventId: 'play_7',
          previousRank: 13,
          currentRank: 14,
          previousPeakRank: 10,
          currentPeakRank: 10,
          minute: 2,
        ),
      ).single;

      expect(rise.eventType, ChartMomentEventType.rankRise);
      expect(fall.eventType, ChartMomentEventType.rankFall);
      expect(rise.deduplicationKey, isNot(fall.deduplicationKey));
    });

    test('supports albums with the same multi-fact semantics', () {
      const album = ChartEntitySnapshot(
        entityId: 'album_a',
        title: 'Album A',
        artistName: 'Artist A',
      );

      final events = detector.detectRankTransition(
        chartType: ChartType.albums,
        entity: album,
        weekStartUtc: weekStart,
        weekEndUtc: weekEnd,
        observation: ChartMomentRankObservation(
          sourceEventId: 'album_play_1',
          entityId: 'album_a',
          hadPreviousObservation: true,
          previousRank: 25,
          currentRank: 20,
          previousPeakRank: 25,
          currentPeakRank: 20,
          observedAt: DateTime.utc(2026, 9, 29, 16),
        ),
        createdAt: createdAt,
      );

      expect(events.first.chartType, ChartType.albums);
      expect(events.first.eventType, ChartMomentEventType.rankRise);

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
