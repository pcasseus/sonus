import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_ranking_comparison_service.dart';

void main() {
  group('MonthlyRankingComparisonService', () {
    const service = MonthlyRankingComparisonService();

    AnalyticsRankedEntity ranking({required String id, required int streams}) {
      return AnalyticsRankedEntity(
        entityId: id,
        qualifiedStreamCount: streams,
        firstQualifiedAt: DateTime.utc(2026, 10, 1),
        lastQualifiedAt: DateTime.utc(2026, 10, 31),
      );
    }

    test('compares current ranking with previous month and lifetime', () {
      final result = service.compare(
        current: [
          ranking(id: 'song_a', streams: 20),
          ranking(id: 'song_b', streams: 15),
        ],
        previous: [
          ranking(id: 'song_b', streams: 30),
          ranking(id: 'song_a', streams: 10),
        ],
        lifetime: [
          ranking(id: 'song_a', streams: 100),
          ranking(id: 'song_b', streams: 80),
        ],
      );

      expect(result, hasLength(2));

      expect(result[0].entityId, 'song_a');
      expect(result[0].rank, 1);
      expect(result[0].previousRank, 2);
      expect(result[0].rankMovement, 1);
      expect(result[0].streams, 20);
      expect(result[0].previousStreams, 10);
      expect(result[0].streamChange.absoluteChange, 10);
      expect(result[0].streamChange.percentChange, 1.0);
      expect(result[0].lifetimeStreams, 100);

      expect(result[1].entityId, 'song_b');
      expect(result[1].rank, 2);
      expect(result[1].previousRank, 1);
      expect(result[1].rankMovement, -1);
      expect(result[1].streams, 15);
      expect(result[1].previousStreams, 30);
      expect(result[1].streamChange.absoluteChange, -15);
      expect(result[1].streamChange.percentChange, -0.5);
      expect(result[1].lifetimeStreams, 80);
    });

    test('marks entity as new when absent from previous month', () {
      final result = service.compare(
        current: [ranking(id: 'song_new', streams: 12)],
        previous: const [],
        lifetime: [ranking(id: 'song_new', streams: 12)],
      );

      expect(result.single.isNew, isTrue);
      expect(result.single.previousRank, isNull);
      expect(result.single.previousStreams, 0);
      expect(result.single.streamChange.percentChange, isNull);
    });

    test(
      'uses current streams when lifetime ranking is unexpectedly missing',
      () {
        final result = service.compare(
          current: [ranking(id: 'song_a', streams: 7)],
          previous: const [],
          lifetime: const [],
        );

        expect(result.single.lifetimeStreams, 7);
      },
    );

    test('keeps current ranking order', () {
      final result = service.compare(
        current: [
          ranking(id: 'song_c', streams: 30),
          ranking(id: 'song_a', streams: 20),
          ranking(id: 'song_b', streams: 10),
        ],
        previous: [
          ranking(id: 'song_a', streams: 20),
          ranking(id: 'song_b', streams: 10),
          ranking(id: 'song_c', streams: 5),
        ],
        lifetime: [
          ranking(id: 'song_a', streams: 100),
          ranking(id: 'song_b', streams: 90),
          ranking(id: 'song_c', streams: 80),
        ],
      );

      expect(result.map((entity) => entity.entityId), [
        'song_c',
        'song_a',
        'song_b',
      ]);
    });

    test('reports unchanged rank when entity holds its position', () {
      final result = service.compare(
        current: [ranking(id: 'song_a', streams: 20)],
        previous: [ranking(id: 'song_a', streams: 15)],
        lifetime: [ranking(id: 'song_a', streams: 100)],
      );

      expect(result.single.rankMovement, 0);
      expect(result.single.stayedAtSameRank, isTrue);
    });
  });
}
