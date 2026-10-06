import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_duration_change.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_ranking_change.dart';

void main() {
  group('monthly insight comparison models', () {
    test('count comparison calculates positive change', () {
      const change = MonthlyRankingChange(
        currentValue: 150,
        previousValue: 100,
      );

      expect(change.absoluteChange, 50);
      expect(change.percentChange, 0.5);
      expect(change.increased, isTrue);
      expect(change.decreased, isFalse);
    });

    test('count comparison reports undefined percent for new activity', () {
      const change = MonthlyRankingChange(currentValue: 10, previousValue: 0);

      expect(change.absoluteChange, 10);
      expect(change.percentChange, isNull);
      expect(change.isNew, isTrue);
    });

    test('zero versus zero has zero percent change', () {
      const change = MonthlyRankingChange(currentValue: 0, previousValue: 0);

      expect(change.absoluteChange, 0);
      expect(change.percentChange, 0);
      expect(change.unchanged, isTrue);
    });

    test('duration comparison calculates positive change', () {
      const change = MonthlyDurationChange(
        current: Duration(hours: 15),
        previous: Duration(hours: 10),
      );

      expect(change.absoluteChange, const Duration(hours: 5));
      expect(change.percentChange, 0.5);
      expect(change.increased, isTrue);
    });

    test('duration comparison supports negative change', () {
      const change = MonthlyDurationChange(
        current: Duration(hours: 8),
        previous: Duration(hours: 10),
      );

      expect(change.absoluteChange, const Duration(hours: -2));

      expect(change.percentChange, -0.2);
      expect(change.decreased, isTrue);
    });

    test('duration percent is undefined when previous month is zero', () {
      const change = MonthlyDurationChange(
        current: Duration(hours: 2),
        previous: Duration.zero,
      );

      expect(change.percentChange, isNull);
    });
  });
}
