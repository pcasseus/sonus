import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/all_time_entry_stats.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_text.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_longevity.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_entry_details.dart';

ChartEntry _entry({
  int rank = 4,
  int streams = 186420771,
  int? previous = 6,
  int weeks = 3,
}) => ChartEntry(
  entity: const ChartEntitySnapshot(
    entityId: 's1',
    title: 'Song',
    artistName: 'Artist',
  ),
  rank: rank,
  qualifiedStreamCount: streams,
  lastQualifiedAt: DateTime.utc(2026, 11, 15),
  peakRank: 2,
  peakAchievedAt: DateTime.utc(2026, 11, 1),
  weeksOnChart: weeks,
  previousFinalRank: previous,
  movement: ChartMovement.up,
);

ChartDetailsData _career({
  AllTimeEntryStats stats = const AllTimeEntryStats(),
  ChartLongevity? longevity,
  bool isSingle = false,
  ChartEntryStatus? status,
  String? movementNote,
  VoidCallback? onShowZones,
}) => ChartDetailsData.career(
  entry: _entry(),
  chartType: ChartType.songs,
  stats: stats,
  weeklyPeakRank: 1,
  longevity: longevity,
  isSingle: isSingle,
  status: status,
  trend: null,
  movementNote: movementNote,
  onShowZones: onShowZones ?? () {},
);

Map<String, ChartDetailStat> _byId(ChartDetailsData data) => {
  for (final stat in data.stats) stat.id: stat,
};

void main() {
  test('groups digits', () {
    expect(chartGroupedCount(0), '0');
    expect(chartGroupedCount(999), '999');
    expect(chartGroupedCount(1000), '1,000');
    expect(chartGroupedCount(186420771), '186,420,771');
  });

  group('career standings', () {
    test('every value is one Sonus calculates', () {
      final stats = _byId(
        _career(
          stats: const AllTimeEntryStats(
            streamsThisWeek: 21,
            streamsSameTimeLastWeek: 20,
            zones: ZoneWeeks({5: 2, 10: 4}),
          ),
        ),
      );

      expect(stats.keys, ['streams', 'change', 'peak', 'zones']);
      expect(stats['streams']!.value, '186,420,771');
      expect(stats['change']!.value, '+5%');
      expect(stats['change']!.trend, WeeklyTrend.up);
      expect(stats['peak']!.value, '#2');
      expect(stats['peak']!.detail, 'Weekly peak #1');
      // The most selective zone reached, with every zone one tap away.
      expect(stats['zones']!.label, 'Weeks in Top 5');
      expect(stats['zones']!.value, '2');
      expect(stats['zones']!.onTap, isNotNull);
    });

    test('no completed zone weeks: said, not invented', () {
      final zones = _byId(_career())['zones']!;
      expect(zones.label, 'Weeks in zones');
      expect(zones.value, '—');
      expect(zones.detail, 'No completed weeks yet');
      expect(zones.onTap, isNull);
    });

    test('milestones: start of week, the movement note, then longevity', () {
      final data = _career(
        movementNote: '+33% position',
        longevity: ChartLongevity(
          weeksAtNumberOne: 0,
          longestNumberOneRun: 0,
          topTenStreak: 3,
          officialWeeks: 5,
          debutWeekStartUtc: DateTime.utc(2026, 10, 25),
          debutRank: 7,
        ),
      );
      expect(data.facts.first, 'Start of week #6');
      expect(data.facts[1], '+33% position');
      expect(data.facts, contains('Top 10 streak: 3 weeks'));
      expect(data.facts, contains('5 official weeks'));
      expect(data.facts.where((f) => f.contains('at #1')), isEmpty);
    });

    test('chips: Single, the lower zone and status', () {
      expect(_career().chips, isEmpty);
      expect(_career(isSingle: true).chips, ['Single']);
      expect(_career(status: ChartEntryStatus.historical).chips, [
        'No longer in your library',
      ]);
    });
  });

  group('weekly charts', () {
    ChartDetailsData weekly({int? bestSoFar}) => ChartDetailsData.weekly(
      entry: _entry(streams: 1234),
      chartType: ChartType.songs,
      previousExtendedRank: null,
      bestSoFarRank: bestSoFar,
      weeklyPeakRank: bestSoFar == null ? null : 2,
      longevity: null,
      isSingle: false,
      status: null,
      trend: null,
      movementNote: 'from Bubbling Under',
    );

    test("that week's streams, peak and weeks on the chart", () {
      final stats = _byId(weekly());
      expect(stats.keys, ['streams', 'peak', 'weeks']);
      expect(stats['streams']!.label, 'Streams this week');
      expect(stats['streams']!.value, '1,234');
      expect(stats['peak']!.label, 'Peak');
      expect(stats['peak']!.value, '#2');
      expect(stats['weeks']!.value, '3');
      expect(weekly().facts, ['Last week #6', 'From Bubbling Under']);
    });

    test('the provisional best so far stays apart from the official peak', () {
      final peak = _byId(weekly(bestSoFar: 1))['peak']!;
      expect(peak.label, 'Best so far');
      expect(peak.value, '#1');
      expect(peak.detail, 'Peak #2');
    });
  });

  testWidgets('weeks in zones open the full breakdown', (tester) async {
    const zones = ZoneWeeks({3: 1, 5: 2, 10: 4});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ChartEntryDetails(
              entityId: 's1',
              data: _career(
                stats: const AllTimeEntryStats(zones: zones),
                onShowZones: () =>
                    showZoneWeeksSheet(context, title: 'Song', zones: zones),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-detail-tap-zones-s1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('charts-zone-weeks-sheet')),
      findsOneWidget,
    );
    expect(find.text('Top 10'), findsOneWidget);
    expect(find.text('4 weeks'), findsOneWidget);
  });
}
