import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';

void main() {
  ChartEntry createEntry({int rank = 1, String entityId = 'song-1'}) {
    return ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: entityId,
        title: 'Test Song',
        artistName: 'Test Artist',
        albumTitle: 'Test Album',
      ),
      rank: rank,
      qualifiedStreamCount: 12,
      lastQualifiedAt: DateTime.utc(2026, 9, 28, 12),
      previousFinalRank: null,
      peakRank: 1,
      peakAchievedAt: DateTime.utc(2026, 9, 28),
      weeksOnChart: 1,
      movement: ChartMovement.newEntry,
    );
  }

  group('ChartEntry', () {
    test('Top 100 entries are officially charting', () {
      expect(createEntry(rank: 100).isOfficiallyCharting, isTrue);
      expect(createEntry(rank: 100).isOffChartStanding, isFalse);
    });

    test('positions 101 through 200 are off-chart standings', () {
      expect(createEntry(rank: 101).isOfficiallyCharting, isFalse);
      expect(createEntry(rank: 101).isOffChartStanding, isTrue);
    });
  });

  group('ChartSnapshot', () {
    test('snapshot without finalizedAt is live', () {
      final snapshot = ChartSnapshot(
        id: 'chart-1',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        entries: [createEntry()],
      );

      expect(snapshot.isLive, isTrue);
      expect(snapshot.isFinalized, isFalse);
    });

    test('snapshot with finalizedAt is finalized', () {
      final snapshot = ChartSnapshot(
        id: 'chart-1',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        finalizedAt: DateTime.utc(2026, 10, 4),
        entries: [createEntry()],
      );

      expect(snapshot.isFinalized, isTrue);
      expect(snapshot.isLive, isFalse);
    });

    test('official entries exclude positions below the Hot 100 cutoff', () {
      final snapshot = ChartSnapshot(
        id: 'chart-1',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        entries: [
          createEntry(rank: 1, entityId: 'song-1'),
          createEntry(rank: 100, entityId: 'song-2'),
          createEntry(rank: 101, entityId: 'song-3'),
          createEntry(rank: 200, entityId: 'song-4'),
        ],
      );

      expect(snapshot.officialEntries.map((entry) => entry.entity.entityId), [
        'song-1',
        'song-2',
      ]);
    });
  });
}
