import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

void main() {
  group('parsing keeps exactly what was written', () {
    test('year, month and day precision', () {
      expect(
        ReleaseDate.tryParse('2026')!.precision,
        ReleaseDatePrecision.year,
      );
      expect(
        ReleaseDate.tryParse('2026-04')!.precision,
        ReleaseDatePrecision.month,
      );
      expect(
        ReleaseDate.tryParse('2026-04-17')!.precision,
        ReleaseDatePrecision.day,
      );
      expect(ReleaseDate.tryParse(' 2011-8-2 ')!.iso, '2011-08-02');
    });

    test('impossible or malformed dates are refused', () {
      for (final text in [
        '',
        '26',
        '2026-13',
        '2026-00',
        '2026-02-30',
        '2026-04-',
        '2026/04/17',
        'April 2026',
        '20261',
      ]) {
        expect(ReleaseDate.tryParse(text), isNull, reason: text);
      }
      expect(ReleaseDate.tryParse('2024-02-29'), isNotNull);
      expect(ReleaseDate.of(2026, null, 3), isNull, reason: 'day needs month');
    });
  });

  test('labels never invent a month or day', () {
    expect(ReleaseDate.of(2026)!.label, '2026');
    expect(ReleaseDate.of(2026, 4)!.label, 'April 2026');
    expect(ReleaseDate.of(2026, 4, 17)!.label, 'April 17, 2026');
  });

  test('the stored instant is the start of the known period, at UTC '
      'midnight', () {
    expect(ReleaseDate.of(2026)!.instant, DateTime.utc(2026));
    expect(ReleaseDate.of(2026, 4)!.instant, DateTime.utc(2026, 4));
    expect(ReleaseDate.of(2026, 4, 17)!.instant, DateTime.utc(2026, 4, 17));
  });

  group('reading stored dates', () {
    test('a precision says how much to show', () {
      final instant = DateTime.utc(2026, 4, 17);
      expect(
        ReleaseDate.fromStored(instant, ReleaseDatePrecision.year).iso,
        '2026',
      );
      expect(
        ReleaseDate.fromStored(instant, ReleaseDatePrecision.month).iso,
        '2026-04',
      );
      expect(ReleaseDate.fromStored(instant, null).iso, '2026-04-17');
    });

    test('an older import saved at local midnight keeps its year', () {
      // DateTime(2019) is local midnight; east of UTC it is December 31,
      // 2018 in UTC.
      final legacy = DateTime(2019).toUtc();
      expect(
        ReleaseDate.fromStored(legacy, ReleaseDatePrecision.year).iso,
        '2019',
      );
    });
  });

  test('newest-first sorting is deterministic for partial dates', () {
    final dates = [
      ReleaseDate.of(2025, 12, 31)!,
      ReleaseDate.of(2026)!,
      ReleaseDate.of(2026, 1, 1)!,
      ReleaseDate.of(2026, 4)!,
      ReleaseDate.of(2026, 1)!,
    ]..sort((a, b) => b.compareTo(a));
    expect(dates.map((d) => d.iso), [
      '2026-04',
      '2026-01-01',
      '2026-01',
      '2026',
      '2025-12-31',
    ]);
  });

  test('isRefinedBy: only a date that keeps everything known', () {
    final month = ReleaseDate.of(2026, 4)!;
    expect(month.isRefinedBy(ReleaseDate.of(2026, 4, 17)!), isTrue);
    expect(month.isRefinedBy(ReleaseDate.of(2026)!), isFalse);
    expect(month.isRefinedBy(ReleaseDate.of(2026, 5)!), isFalse);
  });
}
