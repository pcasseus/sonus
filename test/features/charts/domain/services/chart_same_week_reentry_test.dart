import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

void main() {
  const engine = ChartRankingEngine();

  test(
    'first-time entity becomes reentry after falling out and returning in same live week',
    () {
      final events = <ChartRankingEvent>[
        ChartRankingEvent(
          entityId: 'target-song',
          qualifiedAt: DateTime.utc(2026, 9, 27, 0, 0, 1),
        ),
      ];

      // 101 later one-stream songs push target-song from #1 to #102.
      for (var index = 0; index < 101; index++) {
        events.add(
          ChartRankingEvent(
            entityId: 'competitor-${index.toString().padLeft(3, '0')}',
            qualifiedAt: DateTime.utc(
              2026,
              9,
              27,
              1,
            ).add(Duration(seconds: index)),
          ),
        );
      }

      // Its second stream returns it to the official chart.
      events.add(
        ChartRankingEvent(
          entityId: 'target-song',
          qualifiedAt: DateTime.utc(2026, 9, 27, 2),
        ),
      );

      final result = engine.rank(events: events);

      final target = result.firstWhere(
        (entry) => entry.entityId == 'target-song',
      );

      expect(target.rank, 1);
      expect(target.qualifiedStreamCount, 2);

      expect(target.hasEnteredOfficialChartThisWeek, isTrue);
      expect(target.hasReenteredOfficialChartThisWeek, isTrue);

      expect(target.movement, ChartMovement.reentry);

      // It reached #1 on its original entrance, so its live peak remains #1.
      expect(target.peakRank, 1);
      expect(target.peakAchievedAt, DateTime.utc(2026, 9, 27, 0, 0, 1));

      // Live weeks do not increment the finalized weeks-on-chart counter.
      expect(target.weeksOnChart, 0);
    },
  );
}
