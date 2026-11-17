import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_extended_divider.dart';

/// App Update 1.3 (REF-1.3-06): the career Top 200 and the weekly charts
/// share zone names, so labels name the chart as well.
void main() {
  test('each chart has its own name', () {
    expect(
      ChartZoneNames.chartOf(ChartType.songs, allTime: true),
      'Career Top 200',
    );
    expect(
      ChartZoneNames.chartOf(ChartType.songs, allTime: false),
      'Weekly Hot 100',
    );
    expect(
      ChartZoneNames.chartOf(ChartType.albums, allTime: true),
      'Career Albums & EPs',
    );
    expect(
      ChartZoneNames.chartOf(ChartType.albums, allTime: false),
      'Weekly Albums & EPs',
    );
  });

  test('zones are named with their chart, at the #100/#101 boundary', () {
    String song(int rank, {required bool allTime}) =>
        ChartZoneNames.zoneOf(ChartType.songs, rank, allTime: allTime);
    expect(song(1, allTime: true), 'Career Hot 100');
    expect(song(100, allTime: true), 'Career Hot 100');
    expect(song(101, allTime: true), 'Career Bubbling Under');
    expect(song(114, allTime: true), 'Career Bubbling Under');
    expect(song(14, allTime: false), 'Weekly Hot 100');
    expect(song(101, allTime: false), 'Weekly Bubbling Under');
    expect(
      ChartZoneNames.zoneOf(ChartType.albums, 150, allTime: false),
      'Weekly Albums & EPs #101–200',
    );
  });

  test('the career chart never says "all time" (SN-50 E-Q15A)', () {
    final banned = RegExp(r'all[\s-]*time', caseSensitive: false);
    for (final type in ChartType.values) {
      for (final rank in [1, 150]) {
        expect(
          ChartZoneNames.zoneOf(type, rank, allTime: true),
          isNot(matches(banned)),
        );
      }
      expect(
        ChartZoneNames.chartOf(type, allTime: true),
        isNot(matches(banned)),
      );
    }
  });

  test('the headline names are unchanged', () {
    expect(ChartZoneNames.hot100, 'Sonus Hot 100');
    expect(ChartZoneNames.bubblingUnder, 'Sonus Bubbling Under');
    expect(ChartZoneNames.chart(ChartType.songs), 'Sonus Hot 100');
  });
}
