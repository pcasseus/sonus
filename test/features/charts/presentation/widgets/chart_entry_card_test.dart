import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_longevity.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_entry_card.dart';

void main() {
  const card = ValueKey<String>('card');

  Future<void> pump(
    WidgetTester tester,
    ChartEntry entry, {
    ChartType chartType = ChartType.songs,
    ThemeData? theme,
    VoidCallback? onTap,
    ChartEntryStatus? status,
    bool isAllTime = false,
    double width = 400,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ChartEntryCard(
                  key: card,
                  entry: entry,
                  chartType: chartType,
                  artworkPath: null,
                  onTap: onTap,
                  status: status,
                  isAllTime: isAllTime,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lays out rank, movement, artwork, then title and stats', (
    tester,
  ) async {
    await pump(tester, _entry(rank: 7, previousFinalRank: 9));

    final rank = tester.getCenter(
      find.byKey(const ValueKey<String>('charts-rank-song_7')),
    );
    final movement = tester.getCenter(
      find.byKey(const ValueKey<String>('charts-movement-song_7')),
    );
    final artwork = tester.getCenter(
      find.byKey(const ValueKey<String>('charts-artwork-song_7')),
    );
    final title = tester.getTopLeft(find.text('Song 7'));

    // Movement sits under the rank, both before the artwork.
    expect(movement.dy, greaterThan(rank.dy));
    expect((movement.dx - rank.dx).abs(), lessThan(1));
    expect(artwork.dx, greaterThan(rank.dx));
    expect(title.dx, greaterThan(artwork.dx));

    for (final text in [
      '12 streams',
      'Peak #2',
      'Last week #9',
      '4 weeks',
      'Artist 7 • Album 7',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  // Regression from emulator QA: the rank column sized itself to its
  // movement badge, so a RE-ENTRY row pushed its artwork out of line.
  testWidgets('artwork lines up whatever the movement badge', (tester) async {
    final positions = <double>[];

    for (final movement in [
      ChartMovement.reentry,
      ChartMovement.newEntry,
      ChartMovement.up,
      ChartMovement.same,
    ]) {
      await pump(
        tester,
        _entry(rank: 7, movement: movement, previousFinalRank: 9),
      );
      positions.add(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('charts-artwork-song_7')),
            )
            .dx,
      );
      expect(tester.takeException(), isNull, reason: movement.name);
    }

    expect(positions.toSet(), hasLength(1));
  });

  testWidgets('without an official rank last week the line is neutral', (
    tester,
  ) async {
    await pump(tester, _entry(rank: 7, movement: ChartMovement.newEntry));

    expect(find.text('Last week —'), findsOneWidget);
    expect(find.textContaining('Last week #'), findsNothing);
  });

  testWidgets('album entries show the artist alone', (tester) async {
    await pump(tester, _entry(rank: 7), chartType: ChartType.albums);

    expect(find.text('Artist 7'), findsOneWidget);
    expect(find.text('Artist 7 • Album 7'), findsNothing);
  });

  testWidgets('the card reads as one sentence for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pump(tester, _entry(rank: 7, previousFinalRank: 9), onTap: () {});

    expect(
      tester.getSemantics(find.byKey(card)),
      matchesSemantics(
        label:
            'Number 7, Up 2 places since last week, Song 7, '
            'Artist 7 • Album 7, 12 streams, peak number 2, '
            'last week number 9, 4 weeks on chart',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  group('on the career standings', () {
    testWidgets('compares with the start of the week, not last week', (
      tester,
    ) async {
      await pump(
        tester,
        _entry(rank: 7, previousFinalRank: 9, weeksOnChart: 0),
        isAllTime: true,
      );

      expect(find.text('Start of week #9'), findsOneWidget);
      expect(find.textContaining('Last week'), findsNothing);
      expect(find.text('12 streams'), findsOneWidget);
      expect(find.text('Career peak #2'), findsOneWidget);
      expect(find.textContaining('Weekly peak'), findsNothing);
    });

    testWidgets('shows a weekly chart peak apart from the career peak', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ChartEntryCard(
              key: card,
              entry: _entry(rank: 7, previousFinalRank: 9, weeksOnChart: 0),
              chartType: ChartType.songs,
              artworkPath: null,
              isAllTime: true,
              weeklyPeakRank: 1,
            ),
          ),
        ),
      );

      expect(find.text('Career peak #2'), findsOneWidget);
      expect(find.text('Weekly peak #1'), findsOneWidget);
    });

    testWidgets('shows no chart-week count', (tester) async {
      await pump(
        tester,
        _entry(rank: 7, previousFinalRank: 9, weeksOnChart: 0),
        isAllTime: true,
      );

      expect(find.textContaining('week'), findsOneWidget);
      expect(find.text('0 weeks'), findsNothing);
    });

    testWidgets('a new entry has a neutral start-of-week line', (tester) async {
      await pump(
        tester,
        _entry(rank: 7, movement: ChartMovement.newEntry, weeksOnChart: 0),
        isAllTime: true,
      );

      expect(find.text('Start of week —'), findsOneWidget);
    });

    testWidgets('screen readers hear lifetime terms', (tester) async {
      final semantics = tester.ensureSemantics();

      await pump(
        tester,
        _entry(rank: 7, previousFinalRank: 9, weeksOnChart: 0),
        isAllTime: true,
        onTap: () {},
      );

      expect(
        tester.getSemantics(find.byKey(card)),
        matchesSemantics(
          label:
              'Number 7, Up 2 places since the start of this chart week, '
              'Song 7, Artist 7 • Album 7, 12 lifetime streams, '
              'career peak number 2, number 9 at the start of this week',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  testWidgets('extended standings are flat, labelled and announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
    final colors = theme.extension<SonusColors>()!;

    await pump(
      tester,
      _entry(rank: 150, movement: ChartMovement.newEntry),
      theme: theme,
    );

    expect(
      find.byKey(const ValueKey<String>('charts-extended-song_150')),
      findsOneWidget,
    );
    expect(find.text('BUBBLING UNDER'), findsOneWidget);
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byKey(card),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color,
      Colors.transparent,
    );
    expect(
      tester.widget<Text>(find.text('150')).style!.color,
      colors.textSecondary,
    );
    expect(
      tester.getSemantics(find.byKey(card)).label,
      startsWith('Number 150, Bubbling Under,'),
    );
    semantics.dispose();
  });

  group('top three', () {
    testWidgets('get a raised surface and accent stripe', (tester) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final colors = theme.extension<SonusColors>()!;

      await pump(tester, _entry(rank: 2), theme: theme);

      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(card),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        colors.raisedSurface,
      );
      expect(
        find.byKey(const ValueKey<String>('charts-top-accent-song_2')),
        findsOneWidget,
      );
    });

    testWidgets('keep the raised surface but drop the stripe with '
        'decoration Off', (tester) async {
      final theme = SonusThemeFactory.build(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      );

      await pump(tester, _entry(rank: 1), theme: theme);

      expect(
        find.byKey(const ValueKey<String>('charts-top-accent-song_1')),
        findsNothing,
      );
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(card),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        theme.extension<SonusColors>()!.raisedSurface,
      );
    });

    testWidgets('#1 is the spotlight: accent rank and border', (tester) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final colors = theme.extension<SonusColors>()!;

      await pump(tester, _entry(rank: 1), theme: theme);

      final material = tester.widget<Material>(
        find
            .descendant(of: find.byKey(card), matching: find.byType(Material))
            .first,
      );
      expect(material.color, colors.raisedSurface);
      expect(
        (material.shape as RoundedRectangleBorder).side.color,
        colors.accentPrimary,
      );
      expect(
        tester.widget<Text>(find.text('1')).style!.color,
        colors.accentPrimary,
      );
    });

    testWidgets('#4–10 are restrained; #11 is standard', (tester) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final colors = theme.extension<SonusColors>()!;

      Material material() => tester.widget<Material>(
        find
            .descendant(of: find.byKey(card), matching: find.byType(Material))
            .first,
      );

      await pump(tester, _entry(rank: 4), theme: theme);
      expect(material().color, colors.surface);
      expect(
        (material().shape as RoundedRectangleBorder).side.color,
        colors.border,
      );
      expect(
        find.byKey(const ValueKey<String>('charts-top-accent-song_4')),
        findsOneWidget,
      );

      await pump(tester, _entry(rank: 11), theme: theme);
      expect(material().color, colors.surface);
      expect(
        (material().shape as RoundedRectangleBorder).side.color,
        colors.divider,
      );
      expect(
        find.byKey(const ValueKey<String>('charts-top-accent-song_11')),
        findsNothing,
      );
    });
  });

  group('weekly longevity and context', () {
    final longevity = ChartLongevity(
      weeksAtNumberOne: 2,
      longestNumberOneRun: 2,
      topTenStreak: 4,
      officialWeeks: 6,
      debutWeekStartUtc: DateTime(2026, 8, 30),
      debutRank: 40,
    );

    testWidgets('shows the facts and speaks them', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ChartEntryCard(
              key: card,
              entry: _entry(rank: 3, previousFinalRank: 5),
              chartType: ChartType.songs,
              artworkPath: null,
              longevity: longevity,
            ),
          ),
        ),
      );

      for (final text in [
        '2 weeks at #1',
        'Longest #1 run: 2 weeks',
        'Top 10 streak: 4 weeks',
        'Debut #40 · Aug 30, 2026',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // The stored weeks-on-chart count stands in for official weeks.
      expect(find.text('6 official weeks'), findsNothing);
      final label = tester.getSemantics(find.byKey(card)).label;
      expect(label, contains('2 weeks at number 1'));
      expect(label, contains('in the Top 10 for 4 weeks in a row'));
      expect(label, contains('debuted at number 40'));
      semantics.dispose();
    });

    testWidgets('last week in Bubbling Under is context, not movement', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ChartEntryCard(
              key: card,
              entry: _entry(rank: 80, movement: ChartMovement.newEntry),
              chartType: ChartType.songs,
              artworkPath: null,
              previousExtendedRank: 150,
            ),
          ),
        ),
      );

      expect(find.text('Last week #150 (Bubbling Under)'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(card)).label,
        contains(
          'New entry, Song 80, Artist 80 • Album 80, 12 streams, peak number '
          '2, no official position last week, number 150 below the Top 100',
        ),
      );
      semantics.dispose();
    });

    testWidgets('albums name positions #101–200 plainly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ChartEntryCard(
              entry: _entry(rank: 80, movement: ChartMovement.newEntry),
              chartType: ChartType.albums,
              artworkPath: null,
              previousExtendedRank: 120,
            ),
          ),
        ),
      );

      expect(find.text('Last week #120 (#101–200)'), findsOneWidget);
    });
  });

  testWidgets('status badges are words, not colour alone', (tester) async {
    for (final status in ChartEntryStatus.values) {
      await pump(tester, _entry(rank: 7), status: status);

      expect(find.text(status.label), findsOneWidget, reason: status.name);
    }
  });

  testWidgets('keyboard focus outlines the card', (tester) async {
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());

    await pump(tester, _entry(rank: 7), theme: theme, onTap: () {});

    Border? border() {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(card),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.position == DecorationPosition.foreground &&
                    (widget.decoration as BoxDecoration).borderRadius != null,
              ),
            )
            .first,
      );

      return (box.decoration as BoxDecoration).border as Border?;
    }

    expect(border(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(border()?.top.color, theme.extension<SonusColors>()!.focus);
  });

  testWidgets('fits at 320px with 2x text in every theme', (tester) async {
    for (final id in SonusThemeId.values) {
      await pump(
        tester,
        _entry(
          rank: 188,
          title: 'A very long song title that needs two lines to fit',
          movement: ChartMovement.reentry,
        ),
        theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
        status: ChartEntryStatus.unavailable,
        width: 320,
        textScale: 2,
      );

      expect(tester.takeException(), isNull, reason: id.label);

      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: ChartEntryCard(
                    entry: _entry(rank: 1, previousFinalRank: 1),
                    chartType: ChartType.songs,
                    artworkPath: null,
                    longevity: ChartLongevity(
                      weeksAtNumberOne: 12,
                      longestNumberOneRun: 10,
                      topTenStreak: 20,
                      officialWeeks: 30,
                      debutWeekStartUtc: DateTime(2026, 9, 20),
                      debutRank: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: '${id.label} #1');
      expect(find.text('Top 10 streak: 20 weeks'), findsOneWidget);
    }
  });
}

ChartEntry _entry({
  required int rank,
  int? previousFinalRank,
  ChartMovement movement = ChartMovement.up,
  String? title,
  int weeksOnChart = 4,
}) {
  return ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: 'song_$rank',
      title: title ?? 'Song $rank',
      artistName: 'Artist $rank',
      albumTitle: 'Album $rank',
    ),
    rank: rank,
    qualifiedStreamCount: 12,
    lastQualifiedAt: DateTime.utc(2026, 9, 28),
    previousFinalRank: previousFinalRank,
    peakRank: 2,
    peakAchievedAt: DateTime.utc(2026, 9, 20),
    weeksOnChart: weeksOnChart,
    movement: movement,
  );
}
