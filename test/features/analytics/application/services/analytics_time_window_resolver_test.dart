import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_time_window_resolver.dart';

void main() {
  const resolver = AnalyticsTimeWindowResolver();

  group('AnalyticsTimeWindowResolver', () {
    test('day covers one local calendar day', () {
      final reference = DateTime(2026, 9, 25, 15, 30);

      final window = resolver.resolve(
        period: AnalyticsPeriod.day,
        referenceLocal: reference,
      );

      final expectedStart = DateTime(2026, 9, 25).toUtc();
      final expectedEnd = DateTime(2026, 9, 26).toUtc();

      expect(window.startUtc, expectedStart);
      expect(window.endUtc, expectedEnd);
    });

    test('week begins Sunday and ends the following Sunday', () {
      final reference = DateTime(2026, 9, 25, 15, 30);

      final window = resolver.resolve(
        period: AnalyticsPeriod.week,
        referenceLocal: reference,
      );

      final expectedStart = DateTime(2026, 9, 20).toUtc();
      final expectedEnd = DateTime(2026, 9, 27).toUtc();

      expect(window.startUtc, expectedStart);
      expect(window.endUtc, expectedEnd);
    });

    test('Sunday begins a new week', () {
      final reference = DateTime(2026, 9, 27, 8);

      final window = resolver.resolve(
        period: AnalyticsPeriod.week,
        referenceLocal: reference,
      );

      expect(window.startUtc, DateTime(2026, 9, 27).toUtc());

      expect(window.endUtc, DateTime(2026, 10, 4).toUtc());
    });

    test('Saturday remains in the current Sunday-to-Saturday week', () {
      final reference = DateTime(2026, 9, 26, 23, 59);

      final window = resolver.resolve(
        period: AnalyticsPeriod.week,
        referenceLocal: reference,
      );

      expect(window.startUtc, DateTime(2026, 9, 20).toUtc());

      expect(window.endUtc, DateTime(2026, 9, 27).toUtc());
    });

    test('month handles year rollover', () {
      final reference = DateTime(2026, 12, 18);

      final window = resolver.resolve(
        period: AnalyticsPeriod.month,
        referenceLocal: reference,
      );

      expect(window.startUtc, DateTime(2026, 12).toUtc());

      expect(window.endUtc, DateTime(2027, 1).toUtc());
    });

    test('year covers one local calendar year', () {
      final reference = DateTime(2026, 6, 15);

      final window = resolver.resolve(
        period: AnalyticsPeriod.year,
        referenceLocal: reference,
      );

      expect(window.startUtc, DateTime(2026).toUtc());

      expect(window.endUtc, DateTime(2027).toUtc());
    });

    test('lifetime has no boundaries', () {
      final window = resolver.resolve(
        period: AnalyticsPeriod.lifetime,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(window.startUtc, isNull);
      expect(window.endUtc, isNull);
      expect(window.isLifetime, isTrue);
    });

    test('window uses an exclusive end boundary', () {
      final window = resolver.resolve(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(window.contains(DateTime(2026, 9, 25, 12)), isTrue);

      expect(window.contains(DateTime(2026, 9, 26)), isFalse);
    });
  });
}
