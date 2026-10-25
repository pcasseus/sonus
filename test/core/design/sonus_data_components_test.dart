import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_bar_strip.dart';
import 'package:sonus_next/core/design/widgets/sonus_comparison_indicator.dart';
import 'package:sonus_next/core/design/widgets/sonus_heat_grid.dart';
import 'package:sonus_next/core/design/widgets/sonus_metric_tile.dart';
import 'package:sonus_next/core/design/widgets/sonus_numeric_table.dart';
import 'package:sonus_next/core/design/widgets/sonus_segmented_selector.dart';

void main() {
  final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
  final colors = theme.extension<SonusColors>()!;

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? withTheme,
    double width = 400,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: withTheme ?? theme,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SonusSegmentedSelector', () {
    Widget selector(ValueChanged<String> onChanged) =>
        SonusSegmentedSelector<String>(
          segments: const [
            SonusSegment(value: 'm', label: 'Monthly', icon: Icons.query_stats),
            SonusSegment(value: 'y', label: 'Year', icon: Icons.auto_awesome),
          ],
          selected: 'm',
          onChanged: onChanged,
        );

    testWidgets('selects and reports the chosen value', (tester) async {
      String? chosen;
      await pump(tester, selector((v) => chosen = v));

      await tester.tap(find.text('Year'));
      expect(chosen, 'y');
      // Selection is marked by a checkmark, not colour alone.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('drops decorative icons with large text only', (tester) async {
      await pump(tester, selector((_) {}));
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

      await pump(tester, selector((_) {}), width: 320, textScale: 2);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is styled locally, leaving the shared theme alone', (
      tester,
    ) async {
      await pump(tester, selector((_) {}));

      expect(theme.segmentedButtonTheme.style, isNull);
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .style,
        isNotNull,
      );
    });
  });

  group('SonusComparisonIndicator', () {
    for (final (direction, icon, color) in [
      (SonusComparisonDirection.up, Icons.arrow_upward_rounded, colors.chartUp),
      (
        SonusComparisonDirection.down,
        Icons.arrow_downward_rounded,
        colors.chartDown,
      ),
      (
        SonusComparisonDirection.unchanged,
        Icons.remove_rounded,
        colors.chartSteady,
      ),
      (
        SonusComparisonDirection.isNew,
        Icons.fiber_new_rounded,
        colors.chartNew,
      ),
    ]) {
      testWidgets('${direction.name}: icon carries colour, text and label '
          'carry meaning', (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(
          tester,
          SonusComparisonIndicator(
            comparison: SonusComparison(
              direction: direction,
              text: 'value-${direction.name}',
              spokenLabel: 'spoken ${direction.name}',
            ),
          ),
        );

        expect(tester.widget<Icon>(find.byIcon(icon)).color, color);
        expect(
          tester
              .widget<Text>(find.text('value-${direction.name}'))
              .style!
              .color,
          colors.textSecondary,
        );
        expect(
          find.bySemanticsLabel('spoken ${direction.name}'),
          findsOneWidget,
        );
        semantics.dispose();
      });
    }
  });

  group('SonusMetricTile', () {
    const comparison = SonusComparison(
      direction: SonusComparisonDirection.up,
      text: '+26.3%',
      spokenLabel: 'up 26 percent on last month',
    );

    testWidgets('reads as one sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SonusMetricTile(
          label: 'Streams',
          value: '120',
          previousLabel: 'Sep: 95',
          comparison: comparison,
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Streams, 120, Sep: 95, up 26 percent on last month',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('uses tabular figures and the theme surface', (tester) async {
      await pump(
        tester,
        const SonusMetricTile(label: 'Streams', value: '1,234', featured: true),
      );

      expect(
        tester.widget<Text>(find.text('1,234')).style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(SonusMetricTile),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, colors.raisedSurface);
    });

    testWidgets('fits a narrow column at 2x text in every theme', (
      tester,
    ) async {
      for (final id in SonusThemeId.values) {
        await pump(
          tester,
          const SizedBox(
            width: 140,
            child: SonusMetricTile(
              label: 'Listening time',
              value: '82h 30m',
              previousLabel: 'Sep: 61h',
              comparison: comparison,
              featured: true,
            ),
          ),
          withTheme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          width: 320,
          textScale: 2,
        );
        expect(tester.takeException(), isNull, reason: id.label);
      }
    });
  });

  group('SonusNumericTable', () {
    var taps = 0;

    SonusNumericTable table() => SonusNumericTable(
      storageId: 'tracks',
      identityLabel: 'TRACK',
      columns: const [
        SonusTableColumn(label: 'STREAMS'),
        SonusTableColumn(label: 'CHANGE'),
        SonusTableColumn(label: 'TIME'),
        SonusTableColumn(label: 'LIFETIME'),
      ],
      rows: [
        for (var i = 1; i <= 3; i++)
          SonusTableRow(
            key: ValueKey<String>('row-$i'),
            identity: Text('Track $i'),
            cells: [
              Text('${10 - i}'),
              Text('+$i'),
              Text('${i}h'),
              Text('${100 + i}'),
            ],
            spokenLabel: 'Rank $i, Track $i',
            onTap: () => taps++,
          ),
      ],
    );

    testWidgets('keeps the identity column fixed on wide screens', (
      tester,
    ) async {
      await pump(tester, table(), width: 800);

      final before = tester.getTopLeft(find.text('Track 1'));
      await tester.drag(find.text('LIFETIME'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Track 1')), before);
    });

    testWidgets('rows read as sentences and are tappable', (tester) async {
      final semantics = tester.ensureSemantics();
      taps = 0;
      await pump(tester, table(), width: 800);

      expect(find.bySemanticsLabel('Rank 2, Track 2'), findsOneWidget);
      await tester.tap(find.text('Track 2'));
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('stacks rows on narrow screens and with large text', (
      tester,
    ) async {
      for (final (width, scale) in [(320.0, 1.0), (800.0, 2.0)]) {
        await pump(tester, table(), width: width, textScale: scale);

        expect(find.byKey(const ValueKey<String>('row-1')), findsOneWidget);
        // Every row repeats its column labels when stacked.
        expect(find.text('STREAMS'), findsNWidgets(3));
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(tester.takeException(), isNull, reason: '$width @ $scale');
      }
    });

    // Regression from SN-48K1 K1-0: tables without their own storage slot
    // reopened at the page's vertical offset, hiding the identity column.
    testWidgets('a table built after the page scrolls starts at its first '
        'column', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ListView(
              key: const PageStorageKey<String>('page'),
              children: [
                const SizedBox(height: 1500),
                // Wider than the screen, as on the Monthly tables, so the
                // numeric part really scrolls.
                SonusNumericTable(
                  storageId: 'wide',
                  identityLabel: 'TRACK',
                  columns: [
                    for (var c = 0; c < 6; c++)
                      SonusTableColumn(label: 'COL $c', width: 140),
                  ],
                  rows: [
                    SonusTableRow(
                      key: const ValueKey<String>('wide-row'),
                      identity: const Text('Track 1'),
                      cells: [for (var c = 0; c < 6; c++) Text('$c')],
                      spokenLabel: 'Rank 1, Track 1',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
      page.position.jumpTo(page.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final horizontal = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(horizontal.position.axis, Axis.horizontal);
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      expect(horizontal.position.pixels, 0);
    });
  });

  group('SonusHeatGrid', () {
    List<SonusHeatCell> cells(List<double> values) => [
      for (final (i, v) in values.indexed)
        SonusHeatCell(
          label: '${i + 1}',
          value: v,
          spokenLabel: 'Day ${i + 1}, ${v.toInt()} streams',
        ),
    ];

    double fill(WidgetTester tester, int index) => tester
        .widgetList<FractionallySizedBox>(
          find.byKey(const ValueKey<String>('sonus-heat-fill')),
        )
        .elementAt(index)
        .heightFactor!;

    testWidgets('fill height grows with the value', (tester) async {
      await pump(tester, SonusHeatGrid(cells: cells([0, 2, 5, 10])));

      expect(fill(tester, 0), 0);
      expect(fill(tester, 1), lessThan(fill(tester, 2)));
      expect(fill(tester, 2), lessThan(fill(tester, 3)));
      expect(fill(tester, 3), 1);
    });

    testWidgets('every cell has a label and a spoken value', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, SonusHeatGrid(cells: cells([1, 3]), leadingBlanks: 2));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.bySemanticsLabel('Day 2, 3 streams'), findsOneWidget);
      semantics.dispose();
    });

    test('shades run from a faint tint to the accent', () {
      expect(
        SonusHeatGrid.shadeFor(colors.surface, colors.accentPrimary, 1),
        colors.accentPrimary,
      );
      expect(
        SonusHeatGrid.shadeFor(colors.surface, colors.accentPrimary, 0),
        isNot(colors.accentPrimary),
      );
    });

    testWidgets('fits 320px at 2x text in every theme', (tester) async {
      for (final id in SonusThemeId.values) {
        await pump(
          tester,
          SonusHeatGrid(
            cells: cells([for (var d = 0; d < 31; d++) (d % 7).toDouble()]),
            columnLabels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
          ),
          withTheme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          width: 320,
          textScale: 2,
        );
        expect(tester.takeException(), isNull, reason: id.label);
      }
    });
  });

  group('SonusBarStrip', () {
    testWidgets('bars scale to the largest value and mark the peak', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SonusBarStrip(
          highlightIndex: 2,
          bars: [
            SonusBar(value: 1, spokenLabel: '6 PM, 1 stream', axisLabel: '6P'),
            SonusBar(value: 2, spokenLabel: '7 PM, 2 streams'),
            SonusBar(value: 4, spokenLabel: '8 PM, 4 streams'),
          ],
        ),
      );

      final heights = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((box) => box.heightFactor!)
          .toList();
      expect(heights, [0.25, 0.5, 1]);
      expect(
        find.byKey(const ValueKey<String>('sonus-bar-highlight')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('8 PM, 4 streams, Peak'), findsOneWidget);
      expect(find.text('6P'), findsOneWidget);
      semantics.dispose();
    });
  });
}
