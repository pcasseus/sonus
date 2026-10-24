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
            'Number 7, Up 2 places, Song 7, Artist 7 • Album 7, 12 streams, '
            'peak number 2, last week number 9, 4 weeks on chart',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
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
    expect(find.text('EXTENDED'), findsOneWidget);
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
      startsWith('Number 150, extended standing,'),
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

    testWidgets('position 4 is a standard card', (tester) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());

      await pump(tester, _entry(rank: 4), theme: theme);

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
        theme.extension<SonusColors>()!.surface,
      );
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
    }
  });
}

ChartEntry _entry({
  required int rank,
  int? previousFinalRank,
  ChartMovement movement = ChartMovement.up,
  String? title,
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
    weeksOnChart: 4,
    movement: movement,
  );
}
