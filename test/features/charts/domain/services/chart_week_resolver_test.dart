import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';

void main() {
  const resolver = ChartWeekResolver();

  test('week starts on Sunday and ends on the following Sunday', () {
    final week = resolver.resolve(DateTime(2026, 9, 30, 12));

    expect(week.startUtc, DateTime(2026, 9, 27).toUtc());
    expect(week.endUtc, DateTime(2026, 10, 4).toUtc());
  });

  test('Sunday begins a new chart week', () {
    final week = resolver.resolve(DateTime(2026, 10, 4, 8));

    expect(week.startUtc, DateTime(2026, 10, 4).toUtc());
    expect(week.endUtc, DateTime(2026, 10, 11).toUtc());
  });

  test('Saturday remains in the current chart week', () {
    final week = resolver.resolve(DateTime(2026, 10, 3, 23, 59));

    expect(week.startUtc, DateTime(2026, 9, 27).toUtc());
    expect(week.endUtc, DateTime(2026, 10, 4).toUtc());
  });
}
