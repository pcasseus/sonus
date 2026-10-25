import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_hourly_listening.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/monthly_listening_insights_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/monthly_listening_insights_page.dart';

import '../support/monthly_insights_fixtures.dart';

// SN-48K1 K1-4: the redesigned Monthly Insights dashboard.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(411, 6000),
    double textScale = 1,
    String? artworkPath,
    MonthlyListeningInsights? insights,
    int rowCount = 3,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final controller = MonthlyListeningInsightsController(
      service: FixtureInsightsLoader(insights ?? octoberInsights()),
      enrichment: FixtureInsightsEnricher(
        artworkPath: artworkPath,
        rowCount: rowCount,
      ),
      now: () => DateTime(2026, 10, 20),
    );
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<MonthlyListeningInsightsController?>.value(
        value: controller,
        child: MaterialApp(
          theme: theme ?? SonusThemeFactory.build(const SonusAppearanceSpec()),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const Scaffold(body: MonthlyListeningInsightsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('metric tiles compare each statistic with the previous month', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final headline = find.byKey(
      const ValueKey<String>('monthly-insights-headline-metrics'),
    );
    for (final text in [
      '60',
      'Sep: 40',
      '+50.0% vs previous month',
      '5h',
      'Sep: 4h',
      '12',
      'Sep: 10',
      '+20.0% vs prev',
    ]) {
      expect(
        find.descendant(of: headline, matching: find.text(text)),
        findsWidgets,
        reason: text,
      );
    }
    expect(
      find.bySemanticsLabel(
        'STREAMS, 60, Sep: 40, Up 50.0 percent on the previous month',
      ),
      findsNothing,
      reason: 'tile labels are announced in their natural case',
    );
    expect(
      find.bySemanticsLabel(
        'Streams, 60, Sep: 40, Up 50.0 percent on the previous month',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('hourly strip covers 24 hours and marks the peak', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final hourly = find.byKey(
      const ValueKey<String>('monthly-insights-hourly'),
    );
    expect(hourly, findsOneWidget);
    expect(
      find.descendant(
        of: hourly,
        matching: find.byKey(const ValueKey<String>('sonus-bar-highlight')),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('8 PM, 2h listening, 30 streams, most active hour'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('3 AM, no listening'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the heat grid shows every day of the month', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    for (final day in [1, 2, 31]) {
      expect(
        find.byKey(ValueKey<String>('monthly-insights-heat-2026-10-$day')),
        findsOneWidget,
        reason: 'day $day',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('monthly-insights-heat-2026-10-32')),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('October 3, 6 streams, 23m listening'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('October 2, no listening'), findsOneWidget);
    // Day-level figures stay visible in the day-by-day rail.
    expect(
      find.byKey(const ValueKey<String>('monthly-insights-day-2026-10-3')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('ranking tables keep a frozen identity column on phones', (
    tester,
  ) async {
    await pump(tester);

    for (final id in ['monthly-tracks', 'monthly-artists', 'monthly-albums']) {
      expect(
        find.byKey(PageStorageKey<String>('sonus-table-$id')),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.text('Track 1').hitTestable(), findsOneWidget);
  });

  testWidgets('ranking tables stack at 320dp', (tester) async {
    await pump(tester, size: const Size(320, 8000));

    expect(
      find.byKey(const PageStorageKey<String>('sonus-table-monthly-tracks')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('monthly-insights-track-t1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnails decode at their display size', (tester) async {
    await pump(tester, artworkPath: '/art/cover.png');

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 40);
    }
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
    expect(find.text('Monthly Insights'), findsOneWidget);
  });

  group('every theme', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 16000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Monthly Insights'), findsOneWidget);
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

  // Regression (K1-7 D1): bars showed streams while the highlight marked the
  // hour with the most listening time, so the highlight could be shorter
  // than another bar.
  testWidgets('hourly bars plot listening time, so the peak is tallest', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      insights: octoberInsights(
        hours: const [
          // Most streams, little listening time.
          MonthlyHourlyListening(
            hour: 21,
            streams: 100,
            listeningDuration: Duration(minutes: 30),
          ),
          // Fewer streams, most listening time: the most active hour.
          MonthlyHourlyListening(
            hour: 23,
            streams: 10,
            listeningDuration: Duration(hours: 3),
          ),
        ],
      ),
    );

    final hourly = find.byKey(
      const ValueKey<String>('monthly-insights-hourly'),
    );
    final heights = [
      for (final bar
          in find
              .descendant(
                of: hourly,
                matching: find.byType(FractionallySizedBox),
              )
              .evaluate())
        bar.size!.height,
    ];
    final highlight = tester.getSize(
      find.descendant(
        of: hourly,
        matching: find.byKey(const ValueKey<String>('sonus-bar-highlight')),
      ),
    );
    expect(heights, hasLength(24));
    expect(
      heights.every((height) => height <= highlight.height + 0.01),
      isTrue,
      reason: 'the most active hour is the tallest bar',
    );
    expect(
      find.descendant(
        of: hourly,
        matching: find.text('Listening by hour of day'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '11 PM, 3h listening, 10 streams, most active hour',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('9 PM, 30m listening, 100 streams'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  // Regression (K1-7 D2): a fixed 32px rank column wrapped "10" onto two
  // lines in the stacked cards at 320dp and 2x text.
  testWidgets('double-digit ranks stay on one line at 320dp and 2x text', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(320, 30000),
      textScale: 2,
      rowCount: 10,
    );

    for (final table in ['track-t10', 'artist-a10', 'album-al10']) {
      // The rank leads each card; a later "10" may be a stream count.
      final rank = find
          .descendant(
            of: find.byKey(ValueKey<String>('monthly-insights-$table')),
            matching: find.text('10'),
          )
          .first;
      expect(_isSingleLine(tester, rank), isTrue, reason: table);
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
