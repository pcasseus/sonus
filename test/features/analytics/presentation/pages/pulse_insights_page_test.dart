import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/pulse_insights_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/pulse_insights_page.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';

final now = DateTime(2026, 10, 31, 15);

/// Three tracks by two artists on two releases, played on a few days of
/// each period from August 2026; nothing before.
PulsePeriodData periodData(PulsePeriod p, {bool empty = false}) {
  final first = DateTime(2026, 8, 12, 9);
  final days = <PulseDay>[];
  final track = <String, Map<DateTime, PulseMetrics>>{
    't1': {},
    't2': {},
    't3': {},
  };
  for (final d in p.days) {
    final state = d.isAfter(DateTime(now.year, now.month, now.day))
        ? PulseDayState.future
        : d.isBefore(DateTime(first.year, first.month, first.day))
        ? PulseDayState.beforeHistory
        : PulseDayState.recorded;
    var m = PulseMetrics.zero;
    if (!empty && state == PulseDayState.recorded && d.day % 3 == 0) {
      m = PulseMetrics(
        listened: Duration(minutes: 10 + d.day),
        streams: 2 + d.day % 4,
        allPlays: 3 + d.day % 4,
      );
      track['t${1 + d.day % 3}']![d] = m;
    }
    days.add(PulseDay(localDate: d, state: state, metrics: m));
  }
  PulseMetrics sum(Iterable<PulseMetrics> ms) => ms.fold(
    PulseMetrics.zero,
    (a, b) => PulseMetrics(
      listened: a.listened + b.listened,
      streams: a.streams + b.streams,
      allPlays: a.allPlays + b.allPlays,
    ),
  );
  final totals = {for (final e in track.entries) e.key: sum(e.value.values)};
  final live = {
    for (final e in totals.entries)
      if (!e.value.isEmpty) e.key: e.value,
  };
  final lastActive = {
    for (final id in live.keys) id: DateTime.utc(2026, 8, 13),
  };
  final previous = p.previous;
  final eligible = !previous.startLocal.isBefore(DateTime(2026, 8, 12));
  return PulsePeriodData(
    period: p,
    firstHistoryAt: first.toUtc(),
    totals: sum(days.map((d) => d.metrics)),
    days: days,
    hours: const [],
    previous: PulseComparison(
      period: previous,
      availability: eligible
          ? PulseComparisonAvailability.available
          : PulseComparisonAvailability.notEnoughHistory,
      totals: eligible ? PulseMetrics.zero : null,
      overview: eligible ? PulseOverview.zero : null,
      days: eligible
          ? [for (final _ in previous.days) PulseMetrics.zero]
          : null,
    ),
    samePeriodLastYear: PulseComparison(
      period: p.samePeriodLastYear,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    behavior: null,
    entityTotals: {
      PulseEntityKind.track: live,
      PulseEntityKind.artist: {
        if (live.containsKey('t1') || live.containsKey('t2'))
          'a1': sum([?live['t1'], ?live['t2']]),
        if (live.containsKey('t3')) 'a2': live['t3']!,
      },
      PulseEntityKind.release: {
        if (live.containsKey('t1') || live.containsKey('t2'))
          'r1': sum([?live['t1'], ?live['t2']]),
        if (live.containsKey('t3')) 'r2': live['t3']!,
      },
    },
    entityLastActivity: {
      PulseEntityKind.track: lastActive,
      PulseEntityKind.artist: {
        'a1': DateTime.utc(2026, 8, 13),
        'a2': DateTime.utc(2026, 8, 12),
      },
      PulseEntityKind.release: {
        'r1': DateTime.utc(2026, 8, 13),
        'r2': DateTime.utc(2026, 8, 12),
      },
    },
    entityDays: {PulseEntityKind.track: track},
    releasesOffRankings: const {},
    trackArtists: const {'t1': 'a1', 't2': 'a1', 't3': 'a2'},
    trackReleases: const {'t1': 'r1', 't2': 'r1', 't3': 'r2'},
  );
}

class FakePulseLoader implements PulsePeriodLoader, PulseLifetimeLoader {
  FakePulseLoader({
    this.first,
    this.fail = false,
    this.emptyPeriods = const {},
  });

  DateTime? first;
  bool fail;
  final Set<PulsePeriod> emptyPeriods;
  Completer<void>? gate;

  @override
  Future<DateTime?> firstHistoryAt() async => first;

  @override
  Future<PulsePeriodData> load(PulsePeriod period) async {
    await gate?.future;
    if (fail) throw StateError('unreadable');
    return periodData(period, empty: emptyPeriods.contains(period));
  }

  @override
  Future<int> lifetimeStreams(PulseEntityKind kind, String id) async => 99;
}

class FakePulseDirectory implements PulseDirectoryLoader {
  @override
  Future<PulseEntityDirectory> load(PulsePeriodData data) async =>
      PulseEntityDirectory({
        for (final (id, title) in [
          ('t1', 'A song with a very long title that keeps going and going'),
          ('t2', 'Second Song'),
          ('t3', 'Third Song'),
        ])
          (PulseEntityKind.track, id): PulseEntityInfo(
            kind: PulseEntityKind.track,
            id: id,
            title: title,
            subtitle: 'An artist name long enough to need truncating somewhere',
            artworkPath: null,
            status: PulseEntityStatus.current,
            artistId: id == 't3' ? 'a2' : 'a1',
            albumId: id == 't3' ? 'r2' : 'r1',
          ),
        (PulseEntityKind.artist, 'a1'): const PulseEntityInfo(
          kind: PulseEntityKind.artist,
          id: 'a1',
          title: 'Artist One',
          subtitle: '2 songs · 1 release',
          artworkPath: null,
          status: PulseEntityStatus.current,
          artistId: 'a1',
        ),
        (PulseEntityKind.release, 'r1'): const PulseEntityInfo(
          kind: PulseEntityKind.release,
          id: 'r1',
          title: 'Release One',
          subtitle: 'Artist One · EP',
          artworkPath: null,
          status: PulseEntityStatus.current,
          artistId: 'a1',
          albumId: 'r1',
        ),
      });
}

Future<PulseInsightsController> pumpPage(
  WidgetTester tester, {
  FakePulseLoader? loader,
  SonusAppearanceSpec spec = const SonusAppearanceSpec(
    themeId: SonusThemeId.neonMixtape,
  ),
  Size size = const Size(400, 900),
  double textScale = 1,
  bool provide = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = PulseInsightsController(
    loader: loader ?? FakePulseLoader(first: DateTime(2026, 8, 12, 9).toUtc()),
    directory: FakePulseDirectory(),
    nowLocal: () => now,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: spec.reduceMotion,
      ),
      child: MaterialApp(
        theme: SonusThemeFactory.build(spec),
        home: Scaffold(
          body: provide
              ? ChangeNotifierProvider<PulseInsightsController?>.value(
                  value: controller,
                  child: PulseInsightsPage(nowLocal: () => now),
                )
              : PulseInsightsPage(nowLocal: () => now),
        ),
      ),
    ),
  );
  await controller.initialize();
  await tester.pumpAndSettle();
  return controller;
}

final pageScroll = find
    .descendant(
      of: find.byKey(const ValueKey('pulse-page')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  testWidgets('without a controller the page says Insights are unavailable', (
    tester,
  ) async {
    await pumpPage(tester, provide: false);
    expect(find.byKey(const ValueKey('pulse-unavailable')), findsOneWidget);
  });

  testWidgets('the full page: header, hero, comparisons, overview, stats and '
      'rankings', (tester) async {
    final c = await pumpPage(tester);
    expect(find.text('Sonus Pulse'), findsOneWidget);
    expect(find.text('October 2026'), findsWidgets);
    expect(find.byKey(const ValueKey('pulse-hero')), findsOneWidget);
    expect(find.text('vs previous month'), findsOneWidget);
    expect(find.text('Listening overview'), findsOneWidget);
    expect(c.status, PulseViewStatus.ready);
    await tester.scrollUntilVisible(
      find.text('Top albums & EPs'),
      300,
      scrollable: pageScroll,
    );
    expect(find.text('Release One'), findsOneWidget);
    expect(find.text('Artist One · EP'), findsOneWidget);
  });

  testWidgets('history caption, navigation and the measure toggle', (
    tester,
  ) async {
    final c = await pumpPage(tester);
    expect(find.byKey(const ValueKey('pulse-history-caption')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pulse-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pulse-previous')));
    await tester.pumpAndSettle();
    expect(c.selectedPeriod, PulsePeriod.month(2026, 8));
    expect(find.text('History starts 12 Aug 2026'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('pulse-previous')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('pulse-next')));
    await tester.pumpAndSettle();
    expect(c.selectedPeriod, PulsePeriod.month(2026, 9));

    await tester.tap(find.text('Streams').first);
    await tester.pumpAndSettle();
    expect(c.measure, PulseMeasure.streams);
    expect(find.text('qualified streams'), findsOneWidget);
  });

  testWidgets('Year view adds Months and Milestones; a month bar opens it', (
    tester,
  ) async {
    final c = await pumpPage(tester);
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(c.selectedPeriod, PulsePeriod.year(2026));
    await tester.scrollUntilVisible(
      find.text('Milestones'),
      300,
      scrollable: pageScroll,
    );
    expect(find.text('Months'), findsOneWidget);
    expect(find.text('Most active month'), findsOneWidget);
    expect(find.text('Longest streak'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^September: ')));
    await tester.pumpAndSettle();
    expect(c.selectedPeriod, PulsePeriod.month(2026, 9));
  });

  testWidgets('About these numbers and Show as list sheets', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('pulse-show-list')));
    await tester.pumpAndSettle();
    expect(find.text('October 2026 by day'), findsOneWidget);
    expect(find.text('Sat 31 Oct 2026'), findsOneWidget);
    Navigator.of(tester.element(find.text('October 2026 by day'))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pulse-overview-info')),
      200,
      scrollable: pageScroll,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('pulse-overview-info')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pulse-overview-info')));
    await tester.pumpAndSettle();
    expect(find.text('About these numbers'), findsOneWidget);
    expect(find.textContaining('30 seconds'), findsOneWidget);
  });

  testWidgets('no history, error with Try again, and an empty period', (
    tester,
  ) async {
    await pumpPage(tester, loader: FakePulseLoader());
    expect(find.byKey(const ValueKey('pulse-no-history')), findsOneWidget);

    final failing = FakePulseLoader(
      first: DateTime(2026, 8, 12).toUtc(),
      fail: true,
    );
    final c = await pumpPage(tester, loader: failing);
    expect(find.byKey(const ValueKey('pulse-error')), findsOneWidget);
    failing.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(c.status, PulseViewStatus.ready);

    final empty = FakePulseLoader(
      first: DateTime(2026, 8, 12).toUtc(),
      emptyPeriods: {PulsePeriod.month(2026, 10)},
    );
    await pumpPage(tester, loader: empty);
    expect(find.text('No listening recorded in October 2026'), findsOneWidget);
    expect(find.text('Top artists'), findsNothing);
  });

  testWidgets('a failure after data keeps the page with a banner', (
    tester,
  ) async {
    final loader = FakePulseLoader(first: DateTime(2026, 8, 12).toUtc());
    final c = await pumpPage(tester, loader: loader);
    // September is already cached (October's comparison); August is not.
    await tester.tap(find.byKey(const ValueKey('pulse-previous')));
    await tester.pumpAndSettle();
    loader.fail = true;
    await tester.tap(find.byKey(const ValueKey('pulse-previous')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pulse-error-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('pulse-hero')), findsOneWidget);
    expect(c.data!.period, PulsePeriod.month(2026, 9));
  });

  testWidgets('an open detail closes when the period changes', (tester) async {
    await pumpPage(tester);
    final row = find.byKey(const ValueKey('pulse-row-artist-a1'));
    await tester.scrollUntilVisible(row, 300, scrollable: pageScroll);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('In October 2026'), findsOneWidget);
    expect(find.text('99 lifetime streams'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pulse-previous')),
      -300,
      scrollable: pageScroll,
    );
    await tester.tap(find.byKey(const ValueKey('pulse-previous')));
    await tester.pumpAndSettle();
    expect(find.textContaining('In September'), findsNothing);
    expect(find.text('In October 2026'), findsNothing);
  });

  testWidgets('Open artist goes to the existing artist profile', (
    tester,
  ) async {
    await pumpPage(tester);
    final row = find.byKey(const ValueKey('pulse-row-artist-a1'));
    await tester.scrollUntilVisible(row, 300, scrollable: pageScroll);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final open = find.byKey(const ValueKey('pulse-detail-open-artist'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ArtistProfilePage), findsOneWidget);
  });

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label}: renders at 320 dp and 2x text, wide landscape, '
        'high contrast and reduced motion', (tester) async {
      for (final (spec, size, scale) in [
        (SonusAppearanceSpec(themeId: id), const Size(320, 900), 2.0),
        (
          SonusAppearanceSpec(themeId: id, highContrast: true),
          const Size(900, 500),
          1.0,
        ),
        (
          SonusAppearanceSpec(
            themeId: id,
            reduceMotion: true,
            lowEffects: true,
            decoration: SonusDecorationIntensity.off,
          ),
          const Size(400, 900),
          1.3,
        ),
      ]) {
        await pumpPage(tester, spec: spec, size: size, textScale: scale);
        await tester.tap(find.text('Year'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size $scale');
      }
    });
  }
}
