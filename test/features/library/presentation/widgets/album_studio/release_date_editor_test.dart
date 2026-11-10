// SN-49 / App Update 1.2 BUG-10: the one release date editor saves only as
// much of a date as is known, and fits every supported screen and text size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/presentation/widgets/album_studio/release_date_editor.dart';

import '../../../../../support/release_date_editor_driver.dart';

void main() {
  late ReleaseDateEdit? result;
  late bool closed;

  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> open(WidgetTester tester, ReleaseDate? current) async {
    closed = false;
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () async {
                  result = await showReleaseDateEditor(
                    context,
                    current: current,
                    today: DateTime(2026, 10, 26),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Release date'), findsOneWidget);
  }

  Finder year() => find.byKey(const ValueKey('release-date-year-field'));
  Finder save() => find.byKey(const ValueKey('release-studio-save-date'));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(save());
    await tester.pumpAndSettle();
    await tester.tap(save());
    await tester.pumpAndSettle();
  }

  String preview(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('release-date-preview')))
      .data!;

  DropdownButtonFormField<int?> dayField(WidgetTester tester) =>
      tester.widget<DropdownButtonFormField<int?>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<int?> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'release-date-day-',
              ),
        ),
      );

  int dayItemCount(WidgetTester tester) => tester
      .widget<DropdownButton<int?>>(
        find.descendant(
          of: find.byWidget(dayField(tester)),
          matching: find.byType(DropdownButton<int?>),
        ),
      )
      .items!
      .length;

  testWidgets('a year, a month or a day saves exactly that', (tester) async {
    for (final (typed, expected, label) in [
      ('2026', ReleaseDate.of(2026), 'Saves as 2026 (year only).'),
      (
        '2026-04',
        ReleaseDate.of(2026, 4),
        'Saves as April 2026 (month and year).',
      ),
      ('2026-04-17', ReleaseDate.of(2026, 4, 17), 'Saves as April 17, 2026.'),
    ]) {
      await open(tester, null);
      await enterReleaseDate(tester, typed);
      expect(preview(tester), label);
      await tapSave(tester);
      expect(closed, isTrue);
      final saved = (result! as ReleaseDateSet).date;
      expect(saved, expected);
      expect(saved.precision, expected!.precision);
    }
  });

  testWidgets('opens on the saved date, keeping its precision', (tester) async {
    for (final saved in [
      ReleaseDate.of(2019)!,
      ReleaseDate.of(2019, 3)!,
      ReleaseDate.of(2019, 3, 15)!,
    ]) {
      await open(tester, saved);
      expect(tester.widget<TextField>(year()).controller!.text, '2019');
      await tapSave(tester);
      expect((result! as ReleaseDateSet).date, saved);
    }
  });

  testWidgets('the day waits for a month, and lists only real days', (
    tester,
  ) async {
    await open(tester, null);
    await tester.enterText(year(), '2025');
    await tester.pump();
    expect(dayField(tester).onChanged, isNull);
    expect(find.text('Choose a month first.'), findsOneWidget);

    await chooseReleaseDateMonth(tester, 2);
    expect(dayField(tester).onChanged, isNotNull);
    expect(dayItemCount(tester), 1 + 28);

    await tester.enterText(year(), '2024');
    await tester.pump();
    expect(dayItemCount(tester), 1 + 29);
  });

  testWidgets('a day the new month does not have is cleared, and said so', (
    tester,
  ) async {
    await open(tester, ReleaseDate.of(2024, 1, 31));
    await chooseReleaseDateMonth(tester, 4);

    expect(find.text('Day cleared: April 2024 has 30 days.'), findsOneWidget);
    expect(preview(tester), 'Saves as April 2024 (month and year).');

    await chooseReleaseDateMonth(tester, null);
    expect(preview(tester), 'Saves as 2024 (year only).');
  });

  testWidgets('a missing or impossible year cannot be saved', (tester) async {
    await open(tester, null);
    await chooseReleaseDateMonth(tester, 3);
    expect(find.text('Enter the year.'), findsOneWidget);
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    await tester.enterText(year(), '1850');
    await tester.pump();
    expect(find.text('Use a year from 1900 to 2031.'), findsOneWidget);
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    await tester.enterText(year(), '20');
    await tester.pump();
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    await tester.enterText(year(), '20a6');
    await tester.pump();
    expect(tester.widget<TextField>(year()).controller!.text, '206');
  });

  testWidgets('removing detail asks first; keeping it changes nothing', (
    tester,
  ) async {
    await open(tester, ReleaseDate.of(2019, 3, 15));
    await chooseReleaseDateDay(tester, null);
    await tapSave(tester);

    expect(find.text('Use a less exact date?'), findsOneWidget);
    expect(
      find.text(
        'The saved date is March 15, 2019. Saving March 2019 removes the day.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep the saved date'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    await chooseReleaseDateMonth(tester, null);
    await tapSave(tester);
    expect(
      find.text(
        'The saved date is March 15, 2019. Saving 2019 removes the month and day.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('release-date-confirm-less-precise')),
    );
    await tester.pumpAndSettle();
    expect((result! as ReleaseDateSet).date, ReleaseDate.of(2019));
  });

  testWidgets('Remove date clears it; Cancel returns nothing', (tester) async {
    await open(tester, ReleaseDate.of(2019, 3));
    await tester.tap(find.byKey(const ValueKey('release-date-remove')));
    await tester.pump();
    expect(preview(tester), 'Saving removes the release date.');
    await tapSave(tester);
    expect(result, isA<ReleaseDateCleared>());

    await open(tester, ReleaseDate.of(2019, 3));
    await tester.enterText(year(), '2001');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('the calendar opens on the saved day and fills all three', (
    tester,
  ) async {
    await open(tester, ReleaseDate.of(2019, 3, 15));
    await tester.tap(find.byKey(const ValueKey('release-date-pick-day')));
    await tester.pumpAndSettle();

    expect(find.text('March 2019'), findsOneWidget);
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(preview(tester), 'Saves as March 20, 2019.');
  });

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('fits ${width.toInt()}dp at ${scale}x text, every part '
          'reachable', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await open(tester, ReleaseDate.of(2019, 3, 15));
        expect(tester.takeException(), isNull);

        // Every control is reached by a real tap, so an unreachable or
        // overflowing one fails the test.
        await chooseReleaseDateMonth(tester, 4);
        await chooseReleaseDateDay(tester, 30);
        expect(tester.takeException(), isNull);
        expect(preview(tester), 'Saves as April 30, 2019.');
        await tapSave(tester);
        expect((result! as ReleaseDateSet).date, ReleaseDate.of(2019, 4, 30));
      });
    }
  }

  testWidgets('every control has a label', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, null);
    expect(find.bySemanticsLabel(RegExp('Year')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Month')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Day')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Pick on calendar')), findsOneWidget);
    handle.dispose();
  });
}
