import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_week_label.dart';

/// Local wall-clock fields of a fixed zone, as UTC values.
DateTime Function(DateTime) _zone(int hours) =>
    (instant) => instant.toUtc().add(Duration(hours: hours));

void main() {
  // SN-50 C-30: in a UTC+ zone a week starting at local Sunday midnight
  // begins on Saturday in UTC; the label must read Sunday to Saturday.
  test('a UTC+2 week reads in local dates, Sunday to Saturday', () {
    final start = DateTime.utc(2026, 9, 19, 22); // Sun 20 Sep, 00:00 +2
    final end = DateTime.utc(2026, 9, 26, 22); // Sun 27 Sep, 00:00 +2

    expect(
      chartWeekLabel(start, end, toLocal: _zone(2)),
      'September 20–26, 2026',
    );
    expect(chartShortDate(start, toLocal: _zone(2)), 'Sep 20, 2026');
  });

  test('a UTC-4 week reads the same local week', () {
    final start = DateTime.utc(2026, 9, 20, 4);
    final end = DateTime.utc(2026, 9, 27, 4);

    expect(
      chartWeekLabel(start, end, toLocal: _zone(-4)),
      'September 20–26, 2026',
    );
  });

  test('weeks across months and years name both ends', () {
    expect(
      chartWeekLabel(
        DateTime.utc(2026, 9, 26, 22),
        DateTime.utc(2026, 10, 3, 22),
        toLocal: _zone(2),
      ),
      'September 27 – October 3, 2026',
    );
    expect(
      chartWeekLabel(
        DateTime.utc(2026, 12, 26, 23),
        DateTime.utc(2027, 1, 2, 23),
        toLocal: _zone(1),
      ),
      'December 27, 2026 – January 2, 2027',
    );
  });
}
