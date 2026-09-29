import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  ChartMomentEvent event({
    required ChartMomentEventType eventType,
    int? previousRank,
    int? currentRank,
  }) {
    final occurredAt = DateTime.utc(2026, 9, 28, 20);

    return ChartMomentEvent(
      id: 'moment_test',
      deduplicationKey: 'dedupe_test',
      chartType: ChartType.songs,
      scope: ChartMomentScope.live,
      eventType: eventType,
      entity: const ChartEntitySnapshot(
        entityId: 'song_test',
        title: 'Test Song',
        artistName: 'Test Artist',
        albumTitle: 'Test Album',
      ),
      weekStartUtc: DateTime.utc(2026, 9, 27),
      weekEndUtc: DateTime.utc(2026, 10, 4),
      occurredAt: occurredAt,
      createdAt: occurredAt,
      previousRank: previousRank,
      currentRank: currentRank,
    );
  }

  group('ChartMomentEvent', () {
    test('reports upward rank movement', () {
      final value = event(
        eventType: ChartMomentEventType.rankRise,
        previousRank: 18,
        currentRank: 12,
      );

      expect(value.isRise, isTrue);
      expect(value.isFall, isFalse);
      expect(value.isStationary, isFalse);
      expect(value.movementDistance, 6);
    });

    test('reports downward rank movement', () {
      final value = event(
        eventType: ChartMomentEventType.rankFall,
        previousRank: 8,
        currentRank: 13,
      );

      expect(value.isRise, isFalse);
      expect(value.isFall, isTrue);
      expect(value.isStationary, isFalse);
      expect(value.movementDistance, 5);
    });

    test('reports stationary rank state', () {
      final value = event(
        eventType: ChartMomentEventType.rankSame,
        previousRank: 4,
        currentRank: 4,
      );

      expect(value.isRise, isFalse);
      expect(value.isFall, isFalse);
      expect(value.isStationary, isTrue);
      expect(value.movementDistance, 0);
    });

    test('has no movement distance without both ranks', () {
      final value = event(
        eventType: ChartMomentEventType.debut,
        currentRank: 22,
      );

      expect(value.movementDistance, isNull);
    });

    test('preserves live and finalized scopes as distinct values', () {
      expect(ChartMomentScope.live, isNot(ChartMomentScope.finalized));
    });
  });
}
