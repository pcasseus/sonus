import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rank_observation.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

void main() {
  const engine = ChartRankingEngine();

  group('ChartRankingEngine Moment observations', () {
    test('emits per-play rank observations using qualified-play identity', () {
      final observations = <ChartMomentRankObservation>[];

      engine.rank(
        events: [
          ChartRankingEvent(
            entityId: 'song_a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12),
            sourceEventId: 'play_1',
          ),
          ChartRankingEvent(
            entityId: 'song_b',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12, 1),
            sourceEventId: 'play_2',
          ),
        ],
        onRankObservation: observations.add,
      );

      expect(observations, hasLength(3));

      expect(observations[0].sourceEventId, 'play_1');
      expect(observations[0].entityId, 'song_a');
      expect(observations[0].hadPreviousObservation, isFalse);
      expect(observations[0].isFirstObservation, isTrue);
      expect(observations[0].previousRank, isNull);
      expect(observations[0].previousPeakRank, isNull);
      expect(observations[0].currentPeakRank, 1);
      expect(observations[0].currentRank, 1);

      // song_b's first stream is the most recent tie-breaker, so it takes #1.
      expect(observations[1].sourceEventId, 'play_2');
      expect(observations[1].entityId, 'song_b');
      expect(observations[1].hadPreviousObservation, isFalse);
      expect(observations[1].isFirstObservation, isTrue);
      expect(observations[1].previousRank, isNull);
      expect(observations[1].previousPeakRank, isNull);
      expect(observations[1].currentPeakRank, 1);
      expect(observations[1].currentRank, 1);

      // The same qualified play pushes song_a from #1 to #2.
      expect(observations[2].sourceEventId, 'play_2');
      expect(observations[2].entityId, 'song_a');
      expect(observations[2].previousRank, 1);
      expect(observations[2].currentRank, 2);
    });

    test('preserves reversals as separate observations', () {
      final observations = <ChartMomentRankObservation>[];

      engine.rank(
        events: [
          ChartRankingEvent(
            entityId: 'song_a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12),
            sourceEventId: 'play_1',
          ),
          ChartRankingEvent(
            entityId: 'song_b',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12, 1),
            sourceEventId: 'play_2',
          ),
          ChartRankingEvent(
            entityId: 'song_a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12, 2),
            sourceEventId: 'play_3',
          ),
        ],
        onRankObservation: observations.add,
      );

      final songAChanges = observations
          .where(
            (observation) =>
                observation.entityId == 'song_a' &&
                observation.previousRank != null &&
                observation.previousRank != observation.currentRank,
          )
          .toList(growable: false);

      expect(songAChanges, hasLength(2));

      expect(songAChanges[0].previousRank, 1);
      expect(songAChanges[0].currentRank, 2);
      expect(songAChanges[0].sourceEventId, 'play_2');

      expect(songAChanges[1].previousRank, 2);
      expect(songAChanges[1].currentRank, 1);
      expect(songAChanges[1].sourceEventId, 'play_3');
    });

    test('normalizes a fall beyond Top 200 to outside-chart null', () {
      final observations = <ChartMomentRankObservation>[];

      final events = <ChartRankingEvent>[
        ChartRankingEvent(
          entityId: 'target',
          qualifiedAt: DateTime.utc(2026, 9, 28, 0, 0, 1),
          sourceEventId: 'target_play',
        ),
      ];

      for (var index = 0; index < 200; index++) {
        events.add(
          ChartRankingEvent(
            entityId: 'competitor_$index',
            qualifiedAt: DateTime.utc(
              2026,
              9,
              28,
              0,
              1,
            ).add(Duration(seconds: index)),
            sourceEventId: 'competitor_play_$index',
          ),
        );
      }

      engine.rank(events: events, onRankObservation: observations.add);

      final exits = observations
          .where(
            (observation) =>
                observation.entityId == 'target' &&
                observation.hadPreviousObservation &&
                observation.previousRank == 200 &&
                observation.currentRank == null,
          )
          .toList(growable: false);

      expect(exits, hasLength(1));

      final exit = exits.single;

      expect(exit.wasCharting, isTrue);
      expect(exit.isCharting, isFalse);
      expect(exit.exitedChart, isTrue);
      expect(exit.enteredChart, isFalse);
      expect(exit.changed, isTrue);
      expect(exit.rose, isFalse);
      expect(exit.fell, isFalse);
      expect(exit.sourceEventId, 'competitor_play_199');
    });
    test('does not require source ids when observation is unused', () {
      final result = engine.rank(
        events: [
          ChartRankingEvent(
            entityId: 'song_a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12),
          ),
        ],
      );

      expect(result, hasLength(1));
      expect(result.single.entityId, 'song_a');
      expect(result.single.rank, 1);
    });

    test('does not emit callbacks for events without a source id', () {
      final observations = <ChartMomentRankObservation>[];

      engine.rank(
        events: [
          ChartRankingEvent(
            entityId: 'song_a',
            qualifiedAt: DateTime.utc(2026, 9, 28, 12),
          ),
        ],
        onRankObservation: observations.add,
      );

      expect(observations, isEmpty);
    });
  });
}
