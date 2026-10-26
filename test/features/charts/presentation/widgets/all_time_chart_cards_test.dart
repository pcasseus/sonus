import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/all_time_entry_stats.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/presentation/widgets/all_time_chart_cards.dart';

ChartEntry _entry(int rank, {ChartMovement movement = ChartMovement.up}) =>
    ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: 'song-$rank',
        title: 'bittersweet',
        artistName: 'Madison Beer',
        albumTitle: 'Life Support',
      ),
      rank: rank,
      qualifiedStreamCount: 36,
      lastQualifiedAt: DateTime.utc(2026, 10, 20),
      previousFinalRank: rank + 1,
      peakRank: rank,
      peakAchievedAt: DateTime.utc(2026, 10, 20),
      weeksOnChart: 0,
      movement: movement,
    );

const _stats = AllTimeEntryStats(
  streamsThisWeek: 9,
  streamsSameTimeLastWeek: 8,
  zones: ZoneWeeks({3: 2, 5: 2, 10: 3, 25: 3, 50: 3, 75: 3, 100: 3, 200: 3}),
);

void main() {
  group('weekly change', () {
    String text(int now, int before) => WeeklyChange.of(
      AllTimeEntryStats(streamsThisWeek: now, streamsSameTimeLastWeek: before),
    ).text;

    test('is written once, rounded to a tenth', () {
      expect(text(10, 8), '+25%');
      expect(text(9, 8), '+12.5%');
      expect(text(0, 4), '−100%');
      expect(text(4, 4), '0%');
    });

    test('says when there is nothing to compare with', () {
      expect(text(3, 0), 'New activity');
      expect(text(0, 0), '—');
    });
  });

  test('weeks in zones: the two most selective zones reached', () {
    expect(zoneWeeksSummary(_stats.zones), 'Top 3: 2 · Top 5: 2');
    expect(zoneWeeksSummary(const ZoneWeeks({})), 'No completed weeks yet');
    expect(
      zoneWeeksSummary(const ZoneWeeks({50: 1, 75: 4, 100: 4, 200: 6})),
      'Top 50: 1 · Top 75: 4',
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(430, 1600),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, app) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: app!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('a rich card shows the change once and its statistics', (
    tester,
  ) async {
    await pump(
      tester,
      AllTimeEntryCard(
        entry: _entry(2),
        chartType: ChartType.songs,
        stats: _stats,
        artworkPath: null,
        weeklyPeakRank: 4,
      ),
    );

    expect(find.text('+12.5%'), findsOneWidget);
    expect(find.text('STREAMS'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('PEAK'), findsOneWidget);
    expect(find.text('Weekly #4'), findsOneWidget);
    expect(find.text('WEEK START'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('Weeks in zones · Top 3: 2 · Top 5: 2'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('up 12.5 percent on this time last week')),
      findsOneWidget,
    );
  });

  testWidgets('weeks in zones open the full breakdown', (tester) async {
    await pump(
      tester,
      AllTimeEntryCard(
        entry: _entry(2),
        chartType: ChartType.songs,
        stats: _stats,
        artworkPath: null,
      ),
    );

    final zones = find.byKey(const ValueKey<String>('charts-zones-song-2'));
    expect(tester.getSize(zones).height, greaterThanOrEqualTo(44));

    await tester.tap(zones);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('charts-zone-weeks-sheet')),
      findsOneWidget,
    );
    for (final zone in ZoneWeeks.zones) {
      expect(find.text('Top $zone'), findsOneWidget);
    }
    expect(find.text('2 weeks'), findsNWidgets(2));
    expect(find.text('3 weeks'), findsNWidgets(6));
  });

  testWidgets('the #1 spotlight carries four statistics', (tester) async {
    await pump(
      tester,
      AllTimeSpotlightCard(
        entry: _entry(1, movement: ChartMovement.newEntry),
        chartType: ChartType.songs,
        stats: _stats,
        artworkPath: null,
      ),
    );

    expect(find.text('#1'), findsWidgets);
    expect(find.text('NEW'), findsOneWidget);
    for (final label in [
      'TOTAL STREAMS',
      'WEEKLY CHANGE',
      'ALL-TIME PEAK',
      'WEEKS IN TOP 3',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('+12.5%'), findsOneWidget);
  });

  testWidgets('extended standings are labelled, not dressed as official', (
    tester,
  ) async {
    await pump(
      tester,
      AllTimeEntryCard(
        entry: _entry(150),
        chartType: ChartType.songs,
        stats: const AllTimeEntryStats(),
        artworkPath: null,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('charts-extended-song-150')),
      findsOneWidget,
    );
    expect(find.text('—'), findsOneWidget);
    expect(
      find.text('Weeks in zones · No completed weeks yet'),
      findsOneWidget,
    );
  });

  for (final card in ['spotlight', 'rich']) {
    testWidgets('the $card card fits 320 px at 2x text', (tester) async {
      await pump(
        tester,
        card == 'spotlight'
            ? AllTimeSpotlightCard(
                entry: _entry(1),
                chartType: ChartType.songs,
                stats: _stats,
                artworkPath: null,
                weeklyPeakRank: 3,
              )
            : AllTimeEntryCard(
                entry: _entry(2, movement: ChartMovement.reentry),
                chartType: ChartType.songs,
                stats: _stats,
                artworkPath: null,
                weeklyPeakRank: 3,
              ),
        size: const Size(320, 3000),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      // The change stays readable, not squeezed to its icon.
      expect(tester.getSize(find.text('+12.5%')).width, greaterThan(40));
      // No label breaks inside a word ("STREAM / S").
      for (final label in [
        if (card == 'spotlight') ...[
          'TOTAL STREAMS',
          'WEEKLY CHANGE',
          'ALL-TIME PEAK',
        ] else ...[
          'STREAMS',
          'PEAK',
          'WEEK START',
        ],
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final words = label.split(' ').length;
        expect(
          {
            for (final box in paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            ))
              box.top.round(),
          }.length,
          lessThanOrEqualTo(words),
          reason: label,
        );
      }
    });
  }

  testWidgets('tiles stack under Android-style nonlinear 2x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const _AndroidLikeScaler()),
          child: app!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AllTimeSpotlightCard(
              entry: _entry(1),
              chartType: ChartType.songs,
              stats: const AllTimeEntryStats(streamsThisWeek: 2),
              artworkPath: null,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final streams = tester.getTopLeft(find.text('TOTAL STREAMS'));
    final change = tester.getTopLeft(find.text('WEEKLY CHANGE'));
    expect(change.dy, greaterThan(streams.dy), reason: 'one tile per row');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('New activity'),
    );
    final lines = {
      for (final box in paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 12),
      ))
        box.top.round(),
    };
    expect(lines.length, lessThanOrEqualTo(2));
  });
}

/// Body text doubles; large sizes grow much less, as on Android 14+.
class _AndroidLikeScaler extends TextScaler {
  const _AndroidLikeScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 20 ? fontSize * 2 : 40 + (fontSize - 20) * 0.3;

  @override
  double get textScaleFactor => 2;
}
