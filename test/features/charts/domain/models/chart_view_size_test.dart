import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';

void main() {
  group('ChartViewSize', () {
    test('exposes supported chart limits', () {
      expect(ChartViewSize.values.map((value) => value.limit).toList(), [
        10,
        25,
        50,
        75,
        100,
        200,
      ]);
    });

    test('treats Top 100 as the official chart cutoff', () {
      expect(ChartViewSize.top100.includesOffChartStandings, isFalse);
      expect(ChartViewSize.top200.includesOffChartStandings, isTrue);
      expect(ChartViewSize.officialChartLimit, 100);
    });
  });
}
