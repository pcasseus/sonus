import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/pulse/pulse_delta.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';

void main() {
  group('PulseDelta', () {
    test('up and down give the exact percentage and difference', () {
      final up = PulseDelta.compare(1842, 1645);
      expect(up.kind, PulseDeltaKind.up);
      expect(up.difference, 197);
      expect(up.percent, closeTo(11.975, 0.001));
      expect(up.label, '▲ 12%');
      expect(up.signedDifference, '+197');

      final down = PulseDelta.compare(48, 50);
      expect(down.kind, PulseDeltaKind.down);
      expect(down.label, '▼ 4%');
      expect(down.signedDifference, '−2');
      expect(down.spokenLabel('streams'), 'Down 4%, 2 fewer streams');
    });

    test('from zero is "New", never a percentage', () {
      final fresh = PulseDelta.compare(7, 0);
      expect(fresh.kind, PulseDeltaKind.newValue);
      expect(fresh.percent, isNull);
      expect(fresh.label, 'New');
      expect(fresh.difference, 7);
    });

    test('no change, including zero against zero', () {
      expect(PulseDelta.compare(0, 0).label, 'No change');
      expect(PulseDelta.compare(12, 12).kind, PulseDeltaKind.same);
    });

    test('a real change that rounds to zero reads "<1%"', () {
      expect(PulseDelta.compare(1001, 1000).label, '▲ <1%');
      expect(PulseDelta.compare(999, 1000).label, '▼ <1%');
      expect(PulseDelta.compare(2005, 2000).label, '▲ <1%');
      expect(PulseDelta.compare(20100, 2000).label, '▲ 905%');
      expect(PulseDelta.compare(250000, 10).label, '▲ 2,499,900%');
    });

    test('to zero is a 100% drop', () {
      expect(PulseDelta.compare(0, 9).label, '▼ 100%');
    });
  });

  group('PulseOverviewDeltas', () {
    const current = PulseOverview(
      listened: Duration(minutes: 110, seconds: 59),
      streams: 30,
      allPlays: 41,
      activeDays: 9,
      artists: 6,
      tracks: 20,
    );
    final period = PulsePeriod.month(2026, 10);

    test('no comparison: no deltas at all', () {
      final d = PulseOverviewDeltas.of(current, null);
      expect(d.minutes.kind, PulseDeltaKind.none);
      expect(d.minutes.label, '');
    });

    test('an ineligible comparison never invents numbers', () {
      final d = PulseOverviewDeltas.of(
        current,
        PulseComparison(
          period: period.previous,
          availability: PulseComparisonAvailability.notEnoughHistory,
          totals: null,
        ),
      );
      for (final delta in [
        d.minutes,
        d.streams,
        d.allPlays,
        d.activeDays,
        d.artists,
        d.tracks,
      ]) {
        expect(delta.label, 'Not enough history');
      }
    });

    test('minutes compare in whole minutes, as the tiles show them', () {
      final d = PulseOverviewDeltas.of(
        current,
        PulseComparison(
          period: period.previous,
          availability: PulseComparisonAvailability.available,
          totals: PulseMetrics.zero,
          overview: const PulseOverview(
            listened: Duration(minutes: 100, seconds: 30),
            streams: 0,
            allPlays: 41,
            activeDays: 10,
            artists: 6,
            tracks: 16,
          ),
        ),
      );
      expect(d.minutes.difference, 10, reason: '110 vs 100 whole minutes');
      expect(d.minutes.label, '▲ 10%');
      expect(d.streams.label, 'New');
      expect(d.allPlays.label, 'No change');
      expect(d.activeDays.label, '▼ 10%');
      expect(d.tracks.label, '▲ 25%');
    });
  });
}
