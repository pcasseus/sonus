import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/year_in_sonus_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/year_in_sonus_page.dart';

import '../support/year_in_sonus_fixtures.dart';

// SN-48K1 K1-5: the redesigned Year in Sonus recap.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(411, 9000),
    double textScale = 1,
    String? artworkPath,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final controller = YearInSonusController(
      service: FixtureYearLoader({2026: richYearRecap(2026)}),
      enrichment: FixtureYearEnricher(artworkPath: artworkPath),
      now: () => DateTime(2026, 10, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<YearInSonusController?>.value(
        value: controller,
        child: MaterialApp(
          theme: theme ?? SonusThemeFactory.build(const SonusAppearanceSpec()),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const Scaffold(body: YearInSonusPage()),
        ),
      ),
    );
    await controller.load();
    await tester.pumpAndSettle();
  }

  // Regression: the timeline heading read "January ? December".
  testWidgets('the timeline heading reads January–December', (tester) async {
    await pump(tester);

    expect(find.text('January–December'), findsOneWidget);
    expect(find.textContaining('?'), findsNothing);
  });

  testWidgets('the recap is told in numbered chapters', (tester) async {
    await pump(tester);

    for (final (chapter, title) in [
      ('01', 'Your year in numbers'),
      ('02', 'Milestones'),
      ('03', 'The ones at #1'),
      ('04', 'January–December'),
      ('05', 'Top lists'),
    ]) {
      expect(find.text('CHAPTER $chapter'), findsOneWidget, reason: chapter);
      expect(find.text(title), findsOneWidget, reason: title);
    }

    // Chapters run top to bottom.
    final tops = [
      for (final chapter in ['01', '02', '03', '04', '05'])
        tester.getTopLeft(find.text('CHAPTER $chapter')).dy,
    ];
    expect([...tops]..sort(), tops);
  });

  testWidgets('the peak month is marked with a word', (tester) async {
    await pump(tester);

    final timeline = find.byKey(
      const ValueKey<String>('year-in-sonus-timeline'),
    );
    expect(
      find.descendant(of: timeline, matching: find.text('PEAK')),
      findsOneWidget,
    );
    // It sits on the March row, the recap's most active month.
    expect(
      (tester.getTopLeft(find.text('PEAK')).dy -
              tester
                  .getTopLeft(
                    find.descendant(of: timeline, matching: find.text('Mar')),
                  )
                  .dy)
          .abs(),
      lessThan(12),
    );
  });

  testWidgets('a milestone is read as one sentence', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.bySemanticsLabel(
        RegExp(r'^Most active month\s+March\s+200 streams$'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('artwork decodes at its display size', (tester) async {
    await pump(tester, artworkPath: '/art/cover.png');

    final widths = {
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        (image.image as ResizeImage).width,
    };
    // Champion artwork is 84px and ranking thumbnails 46px.
    expect(widths, {84, 46});
  });

  testWidgets('decoration Off removes marks and texture, keeping content', (
    tester,
  ) async {
    await pump(
      tester,
      theme: SonusThemeFactory.build(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('sonus-motif-mark')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('sonus-surface-texture')),
      findsNothing,
    );
    expect(find.text('Your 2026 in Sonus'), findsOneWidget);
  });

  group('every theme', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 20000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Your 2026 in Sonus'), findsOneWidget);
      });
    }

    testWidgets('high contrast renders without overflow', (tester) async {
      await pump(
        tester,
        theme: SonusThemeFactory.build(
          const SonusAppearanceSpec(highContrast: true),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // Regression (K1-7 D3): a fixed 46px month label wrapped "Jan" into
  // "Ja" and "n" at 2x text.
  testWidgets('month labels stay on one line at 320dp and 2x text', (
    tester,
  ) async {
    await pump(tester, size: const Size(320, 20000), textScale: 2);

    for (final month in [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ]) {
      final label = find.text(month);
      expect(label, findsOneWidget, reason: month);
      expect(_isSingleLine(tester, label), isTrue, reason: month);
    }
    expect(tester.takeException(), isNull);
  });
}

/// Whether [finder]'s text is laid out on a single line.
bool _isSingleLine(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final oneLine = TextPainter(
    text: paragraph.text,
    textScaler: paragraph.textScaler,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final fits = paragraph.size.height <= oneLine.height + 0.5;
  oneLine.dispose();
  return fits;
}
