// App Update 1.2: Sonus Wrapped's plain screens show a WrappedSummary as it
// is, with honest empty, partial, in-progress and error states, and work at
// 320 px with large text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
import 'package:sonus_next/features/wrapped/application/wrapped_service.dart';
import 'package:sonus_next/features/wrapped/application/wrapped_summary.dart';
import 'package:sonus_next/features/wrapped/presentation/wrapped_pages.dart';
import 'package:sonus_next/features/wrapped/presentation/wrapped_scope.dart';

class _Loader implements WrappedLoader {
  _Loader({this.archiveValue = WrappedArchive.empty, this.fail = false});

  WrappedArchive archiveValue;
  final bool fail;
  final Map<PulsePeriod, WrappedSummary> summaries = {};
  final List<PulsePeriod> loads = [];

  @override
  Future<WrappedArchive> archive() async {
    if (fail) throw StateError('no database');
    return archiveValue;
  }

  @override
  Future<WrappedSummary> load(PulsePeriod period) async {
    loads.add(period);
    if (fail) throw StateError('no database');
    return summaries[period] ?? _summary(period);
  }
}

WrappedRankedItem _item(int rank, String title, {String? badge}) =>
    WrappedRankedItem(
      rank: rank,
      id: 'id-$rank',
      title: title,
      subtitle: 'Mira Vale',
      streams: 20 - rank,
      listened: Duration(minutes: 60 - rank),
      status: PulseEntityStatus.current,
      badge: badge,
    );

WrappedSummary _summary(
  PulsePeriod period, {
  WrappedPeriodState state = WrappedPeriodState.complete,
  DateTime? historyStart,
  int streams = 42,
  bool comparison = true,
}) {
  final listening = streams > 0;
  return WrappedSummary(
    period: period,
    state: state,
    historyStartLocal: historyStart,
    totals: listening
        ? WrappedTotals(
            streams: streams,
            listened: const Duration(hours: 2, minutes: 5),
            allPlays: streams + 3,
            activeDays: 9,
            songs: 17,
            artists: 6,
            albums: 4,
          )
        : WrappedTotals.zero,
    topSongs: listening
        ? [_item(1, 'Glass Hours'), _item(2, 'Tidal', badge: 'UNAVAILABLE')]
        : const [],
    topArtists: listening ? [_item(1, 'Mira Vale')] : const [],
    topAlbums: listening ? [_item(1, 'Night Signals')] : const [],
    genres: listening
        ? const [
            WrappedGenreShare(genre: 'Pop', streams: 30, share: 0.75),
            WrappedGenreShare(genre: 'Indie Folk', streams: 10, share: 0.25),
          ]
        : const [],
    streamsWithoutGenre: listening ? 2 : 0,
    days: [
      for (final day in period.days)
        WrappedActivityPoint(
          startLocal: day,
          endLocal: DateTime(day.year, day.month, day.day + 1),
          streams: listening && day.day == 3 ? 5 : 0,
          listened: Duration.zero,
          recorded: true,
        ),
    ],
    weeks: const [],
    months: period.kind == PulsePeriodKind.year
        ? [
            for (var m = 1; m <= 12; m++)
              WrappedMonthRow(
                period: PulsePeriod.month(period.year, m),
                state: m > 3
                    ? WrappedPeriodState.future
                    : WrappedPeriodState.complete,
                totals: m == 2
                    ? const WrappedTotals(
                        streams: 30,
                        listened: Duration(hours: 1),
                        allPlays: 31,
                        activeDays: 5,
                        songs: 9,
                        artists: 3,
                        albums: 2,
                      )
                    : WrappedTotals.zero,
                topSong: m == 2 ? _item(1, 'Glass Hours') : null,
              ),
          ]
        : const [],
    comparison: WrappedComparison(
      previous: period.previous,
      state: comparison
          ? WrappedComparisonState.available
          : WrappedComparisonState.notEnoughHistory,
      totals: comparison
          ? const WrappedTotals(
              streams: 30,
              listened: Duration(hours: 1),
              allPlays: 31,
              activeDays: 5,
              songs: 9,
              artists: 3,
              albums: 2,
            )
          : null,
    ),
    milestones: listening
        ? [
            WrappedMilestone(
              kind: WrappedMilestoneKind.lifetimeStreams,
              value: 100,
              atLocal: DateTime(period.year, period.month, 4, 9),
            ),
          ]
        : const [],
    chartNumberOnes: const [],
    chartWeeks: 0,
  );
}

final _feb = PulsePeriod.month(2027, 2);
final _mar = PulsePeriod.month(2027, 3);
final _jan = PulsePeriod.month(2027, 1);

WrappedArchive _archive() => WrappedArchive(
  historyStartLocal: DateTime(2027, 1, 10),
  years: [PulsePeriod.year(2027)],
  months: [_mar, _feb, _jan],
);

void main() {
  Future<void> pumpWrapped(
    WidgetTester tester,
    _Loader loader, {
    LibraryChangeSignal? changes,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: WrappedScope(
          loader: loader,
          changes: changes,
          child: const WrappedLandingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no history: an honest empty state', (tester) async {
    await pumpWrapped(tester, _Loader());
    expect(find.text('No listening yet'), findsOneWidget);
  });

  testWidgets('a failed load says so, without numbers', (tester) async {
    await pumpWrapped(tester, _Loader(fail: true));
    expect(find.text('Sonus Wrapped couldn\'t load'), findsOneWidget);
  });

  testWidgets('the landing page lists years and months since history began, '
      'with when it starts', (tester) async {
    await pumpWrapped(tester, _Loader(archiveValue: _archive()));
    expect(find.byKey(const ValueKey('wrapped-history-start')), findsOneWidget);
    expect(find.textContaining('10 January 2027'), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-year-2027')), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-month-2027-1')), findsOneWidget);
  });

  testWidgets('a month: its numbers, highlights, comparison and links', (
    tester,
  ) async {
    final loader = _Loader(archiveValue: _archive());
    await pumpWrapped(tester, loader);
    await tester.tap(find.byKey(const ValueKey('wrapped-month-2027-2')));
    await tester.pumpAndSettle();

    String text(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(text('wrapped-streams'), '42');
    expect(text('wrapped-time'), isNotEmpty);
    expect(text('wrapped-songs'), '17');
    expect(text('wrapped-artists'), '6');
    expect(text('wrapped-albums'), '4');
    expect(
      find.textContaining('Most-played song: Glass Hours'),
      findsOneWidget,
    );
    expect(find.textContaining('+12 streams on January'), findsOneWidget);
    expect(find.textContaining('100th stream in Sonus'), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-note')), findsNothing);
  });

  testWidgets('partial, in-progress and empty periods are labelled, and a '
      'comparison without full history is not shown', (tester) async {
    final loader = _Loader(archiveValue: _archive())
      ..summaries[_jan] = _summary(
        _jan,
        historyStart: DateTime(2027, 1, 10, 9),
        comparison: false,
      )
      ..summaries[_mar] = _summary(
        _mar,
        state: WrappedPeriodState.inProgress,
        streams: 0,
      );
    await pumpWrapped(tester, loader);
    await tester.tap(find.byKey(const ValueKey('wrapped-month-2027-1')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Partial: your Sonus listening history starts on '
        '10 January 2027',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('wrapped-no-comparison')), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-comparison')), findsNothing);

    // Later: February, then March.
    await tester.tap(find.byKey(const ValueKey('wrapped-newer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-newer')));
    await tester.pumpAndSettle();
    expect(find.text('March 2027'), findsOneWidget);
    expect(find.textContaining('Month in progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('wrapped-empty')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('wrapped-newer')))
          .onPressed,
      isNull,
      reason: 'nothing after the newest month',
    );
  });

  testWidgets('top lists, genres, activity and the month table', (
    tester,
  ) async {
    await pumpWrapped(tester, _Loader(archiveValue: _archive()));
    await tester.tap(find.byKey(const ValueKey('wrapped-year-2027')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('wrapped-open-songs')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-open-songs')));
    await tester.pumpAndSettle();
    expect(find.text('Glass Hours'), findsOneWidget);
    expect(find.textContaining('UNAVAILABLE'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('wrapped-open-genres')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-open-genres')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pop: 30 streams (75%)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wrapped-genres-unknown')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('wrapped-open-activity')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-open-activity')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wrapped-activity-bars')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('wrapped-open-months')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-open-months')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Top song: Glass Hours'), findsOneWidget);
    expect(find.text('Not yet'), findsWidgets);
  });

  testWidgets('works at 320 px with double text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpWrapped(tester, _Loader(archiveValue: _archive()));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('wrapped-year-2027')),
      100,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('wrapped-year-2027')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wrapped-year-2027')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Everything on the year's page can be reached by scrolling.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('wrapped-open-months')),
      200,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded listening or a library change reloads what is shown', (
    tester,
  ) async {
    final changes = LibraryChangeSignal();
    final loader = _Loader(archiveValue: _archive());
    await pumpWrapped(tester, loader, changes: changes);
    await tester.tap(find.byKey(const ValueKey('wrapped-month-2027-2')));
    await tester.pumpAndSettle();
    expect(loader.loads.where((p) => p == _feb), hasLength(1));

    loader.summaries[_feb] = _summary(_feb, streams: 43);
    changes.notify(LibraryChangeKind.listeningRecorded);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(loader.loads.where((p) => p == _feb), hasLength(2));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('wrapped-streams'))).data,
      '43',
    );
  });
}
