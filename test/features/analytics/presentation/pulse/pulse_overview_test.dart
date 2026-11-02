import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_delta.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/data/pulse_preferences_store.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_colors.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_overview.dart';

const overview = PulseOverview(
  listened: Duration(minutes: 1842),
  streams: 512,
  allPlays: 640,
  activeDays: 27,
  artists: 14,
  tracks: 129,
);

const before = PulseOverview(
  listened: Duration(minutes: 1645),
  streams: 0,
  allPlays: 640,
  activeDays: 28,
  artists: 12,
  tracks: 120,
);

PulseComparison available(PulsePeriod period) => PulseComparison(
  period: period,
  availability: PulseComparisonAvailability.available,
  totals: PulseMetrics.zero,
  overview: before,
);

PulseComparison partial(PulsePeriod period) => PulseComparison(
  period: period,
  availability: PulseComparisonAvailability.notEnoughHistory,
  totals: null,
);

PulsePeriodData periodData({AnalyticsBehaviorMetrics? behavior}) {
  final period = PulsePeriod.month(2026, 10);
  final days = [
    for (final date in period.days)
      PulseDay(
        localDate: date,
        state: PulseDayState.recorded,
        metrics: date.day == 14
            ? const PulseMetrics(
                listened: Duration(minutes: 192),
                streams: 51,
                allPlays: 60,
              )
            : date.day == 20
            ? const PulseMetrics(
                listened: Duration(minutes: 30),
                streams: 6,
                allPlays: 6,
              )
            : PulseMetrics.zero,
      ),
  ];
  return PulsePeriodData(
    period: period,
    firstHistoryAt: DateTime(2026, 10, 1).toUtc(),
    totals: const PulseMetrics(
      listened: Duration(minutes: 222),
      streams: 57,
      allPlays: 66,
    ),
    days: days,
    hours: [
      for (var h = 0; h < 24; h++)
        PulseHour(
          hour: h,
          listened: Duration(minutes: h == 21 ? 90 : (h == 8 ? 40 : 0)),
          streams: 0,
        ),
    ],
    previous: partial(period.previous),
    samePeriodLastYear: partial(period.samePeriodLastYear),
    behavior: behavior,
    entityTotals: const {},
    entityLastActivity: const {},
    entityDays: const {},
    releasesOffRankings: const {},
  );
}

Widget app(
  Widget Function(PulsePalette palette) child, {
  SonusAppearanceSpec spec = const SonusAppearanceSpec(
    themeId: SonusThemeId.afterHours,
  ),
  double width = 400,
  double textScale = 1,
}) => MediaQuery(
  data: MediaQueryData(
    size: Size(width, 900),
    textScaler: TextScaler.linear(textScale),
  ),
  child: MaterialApp(
    theme: SonusThemeFactory.build(spec),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final theme = SonusTheme.of(context);
          final palette = PulsePalette.resolve(
            colors: theme.colors,
            decoration: theme.decoration,
            highContrast: spec.highContrast,
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: width - 32, child: child(palette)),
          );
        },
      ),
    ),
  ),
);

void main() {
  group('overview tiles', () {
    testWidgets('six tiles with exact values and deltas', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          (p) => PulseOverviewGrid(
            overview: overview,
            deltas: PulseOverviewDeltas.of(
              overview,
              available(PulsePeriod.month(2026, 9)),
            ),
            palette: p,
          ),
        ),
      );
      for (final label in [
        'Minutes',
        'Streams',
        'All plays',
        'Active days',
        'Artists',
        'Tracks',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('1,842'), findsOneWidget);
      expect(find.text('▲ 12%'), findsOneWidget);
      expect(find.text('+197 minutes'), findsOneWidget);
      expect(find.text('New'), findsOneWidget, reason: 'streams from zero');
      expect(find.text('No change'), findsOneWidget);
      expect(find.text('▼ 4%'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Minutes: 1,842. Up 12%, 197 more minutes'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pulse-overview-3-columns')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('no comparison shows values only; partial history says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          (p) => PulseOverviewGrid(
            overview: overview,
            deltas: PulseOverviewDeltas.of(overview, null),
            palette: p,
          ),
        ),
      );
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('New'), findsNothing);

      await tester.pumpWidget(
        app(
          (p) => PulseOverviewGrid(
            overview: overview,
            deltas: PulseOverviewDeltas.of(
              overview,
              partial(PulsePeriod.month(2026, 9)),
            ),
            palette: p,
          ),
        ),
      );
      expect(find.text('Not enough history'), findsNWidgets(6));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('two columns below 340 dp and at large text', (tester) async {
      Widget grid(PulsePalette p) => PulseOverviewGrid(
        overview: overview,
        deltas: PulseOverviewDeltas.of(overview, null),
        palette: p,
      );
      await tester.pumpWidget(app(grid, width: 320));
      expect(
        find.byKey(const ValueKey('pulse-overview-2-columns')),
        findsOneWidget,
      );
      await tester.pumpWidget(app(grid, textScale: 2));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pulse-overview-2-columns')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the info button opens the explanation', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        app(
          (p) => PulseOverviewGrid(
            overview: overview,
            deltas: PulseOverviewDeltas.of(overview, null),
            palette: p,
            onInfo: () => opened++,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pulse-overview-info')));
      expect(opened, 1);
      expect(PulseOverviewInfo.paragraphs.join(' '), contains('30 seconds'));
    });
  });

  group('comparison chips', () {
    final period = PulsePeriod.month(2026, 10);

    testWidgets('month: previous, same month last year, none', (tester) async {
      final chosen = <PulseComparisonChoice>[];
      await tester.pumpWidget(
        app(
          (p) => PulseComparisonChips(
            period: period,
            choice: PulseComparisonChoice.previous,
            previous: available(period.previous),
            samePeriodLastYear: partial(period.samePeriodLastYear),
            firstHistoryAt: DateTime(2026, 8, 12, 9).toUtc(),
            palette: p,
            onChanged: chosen.add,
          ),
        ),
      );
      expect(find.text('vs previous month'), findsOneWidget);
      expect(find.text('vs October 2025 · partial history'), findsOneWidget);
      expect(find.text('No comparison'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pulse-comparison-explanation')),
        findsNothing,
      );
      await tester.tap(find.text('No comparison'));
      expect(chosen, [PulseComparisonChoice.none]);
    });

    testWidgets('choosing a partial comparison explains why', (tester) async {
      await tester.pumpWidget(
        app(
          (p) => PulseComparisonChips(
            period: period,
            choice: PulseComparisonChoice.samePeriodLastYear,
            previous: available(period.previous),
            samePeriodLastYear: partial(period.samePeriodLastYear),
            firstHistoryAt: DateTime(2025, 10, 12, 9).toUtc(),
            palette: p,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        find.text(
          'Your history starts 12 Oct 2025, so October 2025 is incomplete.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('year: vs the previous year, or none', (tester) async {
      final year = PulsePeriod.year(2026);
      await tester.pumpWidget(
        app(
          (p) => PulseComparisonChips(
            period: year,
            choice: PulseComparisonChoice.previous,
            previous: available(year.previous),
            samePeriodLastYear: available(year.previous),
            firstHistoryAt: DateTime(2024, 1, 1).toUtc(),
            palette: p,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('vs 2025'), findsOneWidget);
      expect(find.text('No comparison'), findsOneWidget);
      expect(find.textContaining('vs October'), findsNothing);
    });
  });

  group('more about this period', () {
    AnalyticsBehaviorMetrics behavior({int ended = 40}) =>
        AnalyticsBehaviorMetrics(
          period: AnalyticsPeriod.month,
          window: PulsePeriod.month(2026, 10).window,
          sessionCount: 45,
          endedSessionCount: ended,
          completedSessionCount: 30,
          skippedSessionCount: 6,
          stoppedSessionCount: 2,
          replacedSessionCount: 1,
          interruptedSessionCount: 1,
          failedSessionCount: 0,
          firstSessionStartedAt: null,
          lastSessionStartedAt: null,
          activeQualifiedDayCount: 2,
          averageQualifiedStreamsPerActiveDay: 28.5,
          averageQualifiedStreamsPerCalendarDay: 1.8,
          peakDay: null,
        );

    test('keeps the existing statistics and their meaning', () {
      final rows = Map.fromEntries(
        PulseMoreStats.rows(
          periodData(behavior: behavior()),
        ).map((r) => MapEntry(r.$1, r.$2)),
      );
      expect(rows['Active days'], '2 / 31');
      expect(rows['Average streams / active day'], '28.5');
      expect(rows['Busiest day'], '14 Oct · 51 streams');
      expect(rows['Longest listening day'], '14 Oct, 3 h 12 m');
      expect(rows['Most active hour'], '9 PM · 1 h 30 m');
      expect(rows['Completion rate'], '75.0%', reason: '30 of 40 ended');
      expect(rows['Skip rate'], '15.0%');
    });

    test('rates without ended plays are a dash, not 0%', () {
      final rows = Map.fromEntries(
        PulseMoreStats.rows(
          periodData(behavior: behavior(ended: 0)),
        ).map((r) => MapEntry(r.$1, r.$2)),
      );
      expect(rows['Completion rate'], '—');
      expect(PulseMoreStats.rows(periodData()).last, ('Skip rate', '—'));
    });

    testWidgets('collapsed until opened; reduced motion opens instantly', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          (p) => PulseMoreStats(
            data: periodData(behavior: behavior()),
            palette: p,
          ),
          spec: const SonusAppearanceSpec(
            themeId: SonusThemeId.haze2017,
            reduceMotion: true,
          ),
        ),
      );
      expect(find.text('More about October 2026'), findsOneWidget);
      expect(find.text('Skip rate'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pulse-more-toggle')));
      await tester.pump();
      expect(find.text('Skip rate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label}: overview, chips and stats render in every '
        'mode at 320 dp', (tester) async {
      for (final spec in [
        SonusAppearanceSpec(themeId: id),
        SonusAppearanceSpec(themeId: id, highContrast: true),
        SonusAppearanceSpec(
          themeId: id,
          decoration: SonusDecorationIntensity.off,
        ),
        SonusAppearanceSpec(themeId: id, lowEffects: true),
      ]) {
        final period = PulsePeriod.month(2026, 10);
        await tester.pumpWidget(
          KeyedSubtree(
            key: ValueKey(spec),
            child: app(
              (p) => Column(
                children: [
                  PulseOverviewGrid(
                    overview: overview,
                    deltas: PulseOverviewDeltas.of(
                      overview,
                      available(period.previous),
                    ),
                    palette: p,
                  ),
                  PulseComparisonChips(
                    period: period,
                    choice: PulseComparisonChoice.samePeriodLastYear,
                    previous: available(period.previous),
                    samePeriodLastYear: partial(period.samePeriodLastYear),
                    firstHistoryAt: DateTime(2026, 8, 1).toUtc(),
                    palette: p,
                    onChanged: (_) {},
                  ),
                  PulseMoreStats(data: periodData(), palette: p),
                ],
              ),
              spec: spec,
              width: 320,
            ),
          ),
        );
        final toggle = find.byKey(const ValueKey('pulse-more-toggle'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text('Completion rate'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
