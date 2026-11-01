import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_colors.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_format.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_hero.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_ring_layout.dart';

/// October 2026: history starts on the 3rd, today is the 28th. Day d has d
/// minutes and d % 4 streams; the 10th is silent; "song_x" has half of
/// each even day.
PulsePeriodData october({PulseComparison? previous}) {
  final period = PulsePeriod.month(2026, 10);
  final days = <PulseDay>[];
  final itemDays = <DateTime, PulseMetrics>{};
  var listened = Duration.zero;
  var streams = 0;
  for (final date in period.days) {
    final d = date.day;
    if (d < 3) {
      days.add(
        PulseDay(
          localDate: date,
          state: PulseDayState.beforeHistory,
          metrics: PulseMetrics.zero,
        ),
      );
    } else if (d > 28) {
      days.add(
        PulseDay(
          localDate: date,
          state: PulseDayState.future,
          metrics: PulseMetrics.zero,
        ),
      );
    } else {
      final m = d == 10
          ? PulseMetrics.zero
          : PulseMetrics(
              listened: Duration(minutes: d),
              streams: d % 4,
              allPlays: d % 4 + 1,
            );
      listened += m.listened;
      streams += m.streams;
      days.add(
        PulseDay(localDate: date, state: PulseDayState.recorded, metrics: m),
      );
      if (d.isEven && d != 10) {
        itemDays[date] = PulseMetrics(
          listened: Duration(seconds: d * 30),
          streams: (d % 4) ~/ 2,
          allPlays: 1,
        );
      }
    }
  }
  final totals = PulseMetrics(
    listened: listened,
    streams: streams,
    allPlays: 0,
  );
  return PulsePeriodData(
    period: period,
    firstHistoryAt: DateTime(2026, 10, 3, 9).toUtc(),
    totals: totals,
    days: days,
    hours: const [],
    previous:
        previous ??
        PulseComparison(
          period: period.previous,
          availability: PulseComparisonAvailability.notEnoughHistory,
          totals: null,
        ),
    samePeriodLastYear: PulseComparison(
      period: period.samePeriodLastYear,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    behavior: null,
    entityTotals: const {},
    entityLastActivity: const {},
    entityDays: {
      PulseEntityKind.track: {'song_x': itemDays},
    },
    releasesOffRankings: const {},
  );
}

PulsePeriodData year2026() {
  final period = PulsePeriod.year(2026);
  return PulsePeriodData(
    period: period,
    firstHistoryAt: DateTime(2026, 1, 1).toUtc(),
    totals: const PulseMetrics(
      listened: Duration(minutes: 365),
      streams: 365,
      allPlays: 365,
    ),
    days: [
      for (final date in period.days)
        PulseDay(
          localDate: date,
          state: PulseDayState.recorded,
          metrics: const PulseMetrics(
            listened: Duration(minutes: 1),
            streams: 1,
            allPlays: 1,
          ),
        ),
    ],
    hours: const [],
    previous: PulseComparison(
      period: period.previous,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    samePeriodLastYear: PulseComparison(
      period: period.previous,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    behavior: null,
    entityTotals: const {},
    entityLastActivity: const {},
    entityDays: const {},
    releasesOffRankings: const {},
  );
}

SonusAppearanceSpec spec({
  SonusThemeId theme = SonusThemeId.neonMixtape,
  bool reduceMotion = false,
  bool highContrast = false,
  SonusDecorationIntensity decoration = SonusDecorationIntensity.standard,
}) => SonusAppearanceSpec(
  themeId: theme,
  reduceMotion: reduceMotion,
  highContrast: highContrast,
  decoration: decoration,
);

void main() {
  group('geometry', () {
    test('a month runs clockwise from 12 o\'clock, one spoke per day', () {
      final g = PulseRingGeometry.of(
        PulsePeriod.month(2026, 10),
        const Size.square(300),
      );
      expect(g.angles, hasLength(31));
      expect(g.angles.first, 0);
      for (var i = 1; i < 31; i++) {
        expect(g.angles[i], greaterThan(g.angles[i - 1]));
      }
      final top = g.point(0, g.outerRadius);
      expect(top.dx, closeTo(150, 0.001));
      expect(top.dy, lessThan(150), reason: 'day 1 points up');
      final right = g.point(math.pi / 2, g.outerRadius);
      expect(right.dx, greaterThan(150), reason: 'then clockwise');
    });

    test('a year has 365 hairline spokes in 12 arcs with gaps', () {
      final period = PulsePeriod.year(2026);
      final g = PulseRingGeometry.of(period, const Size.square(300));
      expect(g.angles, hasLength(365));
      expect(g.spokeWidth, 1.2);
      final steps = [
        for (var i = 1; i < 365; i++) g.angles[i] - g.angles[i - 1],
      ];
      final normal = steps.reduce(math.min);
      final gaps = steps.where((s) => s > normal * 1.5).length;
      expect(gaps, 11, reason: 'between each pair of months');
      expect(g.angles.last, lessThan(2 * math.pi));
    });

    test('hit testing finds the spoke; the centre and outside clear', () {
      final g = PulseRingGeometry.of(
        PulsePeriod.month(2026, 10),
        const Size.square(300),
      );
      for (final i in [0, 7, 15, 30]) {
        final p = g.point(g.angles[i], (g.innerRadius + g.outerRadius) / 2);
        expect(g.hitTest(p), i);
      }
      expect(g.hitTest(g.center), isNull);
      expect(g.hitTest(const Offset(0, 0)), isNull);
    });
  });

  group('layout', () {
    test('length is linear in value; the busiest day reaches the edge and '
        'the brightest step', () {
      final data = october();
      final layout = PulseRingLayout.build(
        data: data,
        measure: PulseMeasure.minutes,
      );
      final busiest = layout.spokes[27];
      expect(busiest.fraction, 1);
      expect(busiest.tipPosition, 1);
      expect(layout.spokes[13].fraction, closeTo(14 / 28, 1e-9));
      expect(layout.spokes[9].value, 0, reason: 'the silent 10th');
      expect(layout.spokes[0].state, PulseDayState.beforeHistory);
      expect(layout.spokes[30].state, PulseDayState.future);
      final recorded = [for (var d = 3; d <= 28; d++) d == 10 ? 0 : d];
      final mean = recorded.reduce((a, b) => a + b) / recorded.length;
      expect(layout.averageFraction, closeTo(mean / 28, 1e-9));
    });

    test('the comparison ghost shares the scale and may be longer', () {
      final ghostDays = [
        for (var d = 1; d <= 31; d++)
          PulseMetrics(
            listened: Duration(minutes: d == 5 ? 56 : 1),
            streams: 0,
            allPlays: 0,
          ),
      ];
      final layout = PulseRingLayout.build(
        data: october(),
        measure: PulseMeasure.minutes,
        comparisonDays: ghostDays,
      );
      expect(layout.spokes[4].ghostFraction, 1);
      expect(layout.spokes[27].fraction, 0.5);
      expect(layout.spokes[27].tipPosition, 1, reason: 'colour is per period');
    });

    test('the selected item is never longer than its day, and absent on '
        'days without it', () {
      final data = october();
      for (final measure in [PulseMeasure.minutes, PulseMeasure.streams]) {
        final layout = PulseRingLayout.build(
          data: data,
          measure: measure,
          itemDays: data.daySeriesFor(PulseEntityKind.track, 'song_x'),
        );
        for (final spoke in layout.spokes) {
          expect(spoke.itemFraction, lessThanOrEqualTo(spoke.fraction));
          final day = data.days[spoke.index].localDate.day;
          if (day.isOdd) expect(spoke.itemFraction, 0);
        }
      }
    });
  });

  group('hero', () {
    Future<GlobalKey<PulseHeroState>> pump(
      WidgetTester tester, {
      PulsePeriodData? data,
      PulseMeasure measure = PulseMeasure.minutes,
      PulseItemFocus? item,
      SonusAppearanceSpec? appearance,
      ValueChanged<PulsePeriod>? onOpenMonth,
      VoidCallback? onShowList,
      bool disableAnimations = false,
    }) async {
      final key = GlobalKey<PulseHeroState>();
      final s = appearance ?? spec();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: disableAnimations,
          ),
          child: MaterialApp(
            theme: SonusThemeFactory.build(s),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final theme = SonusTheme.of(context);
                  return Center(
                    child: SizedBox(
                      width: 320,
                      child: PulseHero(
                        key: key,
                        data: data ?? october(),
                        measure: measure,
                        item: item,
                        palette: PulsePalette.resolve(
                          colors: theme.colors,
                          decoration: theme.decoration,
                          highContrast: s.highContrast,
                        ),
                        onOpenMonth: onOpenMonth,
                        onShowList: onShowList,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return key;
    }

    Offset spokeCenter(WidgetTester tester, PulsePeriod period, int index) {
      final box = tester.getRect(find.byType(CustomPaint).last);
      final g = PulseRingGeometry.of(period, box.size);
      return box.topLeft +
          g.point(g.angles[index], (g.innerRadius + g.outerRadius) / 2);
    }

    String readout(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('pulse-readout'))).data!;

    testWidgets('the centre names the total; the readout hints the longest '
        'spoke', (tester) async {
      await pump(tester);
      final data = october();
      final expected = PulseFormat.minutes(data.totals.listened);
      expect(find.text(PulseFormat.grouped(expected)), findsOneWidget);
      expect(find.text('minutes listened'), findsOneWidget);
      expect(readout(tester), 'The longest spoke is 28 Oct, 28 m');
    });

    testWidgets('tap selects the nearest spoke with an exact readout; the '
        'centre clears it', (tester) async {
      final key = await pump(tester);
      final data = october();
      await tester.tapAt(spokeCenter(tester, data.period, 13));
      await tester.pump();
      expect(key.currentState!.selectedDay, 13);
      expect(readout(tester), 'Wed 14 Oct 2026 · 14 min listened · 2 streams');

      await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
      await tester.pump();
      expect(key.currentState!.selectedDay, isNull);
    });

    testWidgets('drag scrubs day by day', (tester) async {
      final key = await pump(tester);
      final period = october().period;
      final gesture = await tester.startGesture(spokeCenter(tester, period, 4));
      await gesture.moveTo(spokeCenter(tester, period, 6));
      await gesture.moveTo(spokeCenter(tester, period, 8));
      await gesture.up();
      await tester.pump();
      expect(key.currentState!.selectedDay, 8);
    });

    testWidgets('keyboard: arrows move a day, Home and End jump', (
      tester,
    ) async {
      final key = await pump(tester);
      await tester.tapAt(spokeCenter(tester, october().period, 5));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(key.currentState!.selectedDay, 6);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(key.currentState!.selectedDay, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(key.currentState!.selectedDay, 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(key.currentState!.selectedDay, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(key.currentState!.selectedDay, isNull);
    });

    testWidgets('screen readers: one adjustable node with the summary and '
        'a "Show as list" action', (tester) async {
      final handle = tester.ensureSemantics();
      var listShown = 0;
      final key = await pump(tester, onShowList: () => listShown++);
      final data = october();

      final node = tester.getSemantics(
        find.bySemanticsLabel(PulseFormat.summary(data, PulseMeasure.minutes)),
      );
      expect(
        node.label,
        startsWith('October 2026: 393 minutes across 26 recorded days'),
      );
      expect(node.label, endsWith('busiest day 28 October'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );

      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(key.currentState!.selectedDay, 0);

      final show = node.getSemanticsData().customSemanticsActionIds!;
      expect(show, isNotEmpty);
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        show.first,
      );
      expect(listShown, 1);
      handle.dispose();
    });

    testWidgets('the day list is the accessible table', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(spec()),
          home: Scaffold(
            body: SingleChildScrollView(child: PulseDayList(data: october())),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Wed 14 Oct 2026: 14 minutes, 2 streams'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Thu 1 Oct 2026: before your history starts'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Sat 31 Oct 2026: not yet'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an open item adds its part to the readout', (tester) async {
      await pump(
        tester,
        item: const PulseItemFocus(
          kind: PulseEntityKind.track,
          id: 'song_x',
          name: 'Song X',
        ),
      );
      await tester.tapAt(spokeCenter(tester, october().period, 13));
      await tester.pump();
      expect(
        readout(tester),
        'Wed 14 Oct 2026 · 14 min listened · 2 streams · Song X 7 min',
      );
    });

    testWidgets('year: a second tap or "Open {month}" opens that month', (
      tester,
    ) async {
      final opened = <PulsePeriod>[];
      await pump(tester, data: year2026(), onOpenMonth: opened.add);
      final period = PulsePeriod.year(2026);
      final march3 = period.days.indexOf(DateTime(2026, 3, 3));

      await tester.tapAt(spokeCenter(tester, period, march3));
      await tester.pump();
      expect(find.text('Open March'), findsOneWidget);
      await tester.tap(find.text('Open March'));
      expect(opened, [PulsePeriod.month(2026, 3)]);

      await tester.tapAt(spokeCenter(tester, period, march3));
      await tester.pump();
      expect(opened, hasLength(2));
    });

    testWidgets('a data change sweeps; reduced motion swaps instantly', (
      tester,
    ) async {
      await pump(tester);
      await pump(tester, measure: PulseMeasure.streams);
      expect(tester.hasRunningAnimations, isFalse, reason: 'settled');

      final key = await pump(tester, disableAnimations: true);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: SonusThemeFactory.build(spec()),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final theme = SonusTheme.of(context);
                  return Center(
                    child: SizedBox(
                      width: 320,
                      child: PulseHero(
                        key: key,
                        data: october(),
                        measure: PulseMeasure.streams,
                        palette: PulsePalette.resolve(
                          colors: theme.colors,
                          decoration: theme.decoration,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with motion, a measure change animates', (tester) async {
      final key = await pump(tester);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: MaterialApp(
            theme: SonusThemeFactory.build(spec()),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final theme = SonusTheme.of(context);
                  return Center(
                    child: SizedBox(
                      width: 320,
                      child: PulseHero(
                        key: key,
                        data: october(),
                        measure: PulseMeasure.streams,
                        palette: PulsePalette.resolve(
                          colors: theme.colors,
                          decoration: theme.decoration,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
    });

    for (final id in SonusThemeId.values) {
      testWidgets('paints every state in ${id.label}, also with high '
          'contrast and Decoration Off', (tester) async {
        for (final s in [
          spec(theme: id),
          spec(theme: id, highContrast: true),
          spec(theme: id, decoration: SonusDecorationIntensity.off),
        ]) {
          final key = await pump(
            tester,
            appearance: s,
            item: const PulseItemFocus(
              kind: PulseEntityKind.track,
              id: 'song_x',
              name: 'Song X',
            ),
          );
          await tester.tapAt(spokeCenter(tester, october().period, 13));
          await tester.pump();
          expect(key.currentState!.selectedDay, 13);
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('fits 320 dp at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: MaterialApp(
            theme: SonusThemeFactory.build(spec()),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final theme = SonusTheme.of(context);
                  return SingleChildScrollView(
                    child: PulseHero(
                      data: october(),
                      measure: PulseMeasure.minutes,
                      palette: PulsePalette.resolve(
                        colors: theme.colors,
                        decoration: theme.decoration,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
