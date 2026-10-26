// SN-49: the release date editor saves only as much of a date as is known.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/presentation/widgets/album_studio/release_date_editor.dart';

void main() {
  late ReleaseDateEdit? result;
  late bool closed;

  Future<void> open(WidgetTester tester, ReleaseDate? current) async {
    closed = false;
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
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
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('release-studio-date-field'));
  Finder save() => find.byKey(const ValueKey('release-studio-save-date'));

  String preview(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('release-date-preview')))
      .data!;

  testWidgets('a typed year, month or day saves exactly that', (tester) async {
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
      await tester.enterText(field(), typed);
      await tester.pump();
      expect(preview(tester), label);
      await tester.tap(save());
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect((result! as ReleaseDateSet).date, expected);
    }
  });

  testWidgets('an impossible date cannot be saved', (tester) async {
    await open(tester, null);
    await tester.enterText(field(), '2026-02-30');
    await tester.pump();

    expect(
      find.text('Use 2026, 2026-04 or 2026-04-17, with a real month and day.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(save()).onPressed, isNull);

    await tester.enterText(field(), '1850');
    await tester.pump();
    expect(find.text('Use a year from 1900 to 2031.'), findsOneWidget);
  });

  testWidgets('a month can be chosen without inventing a day', (tester) async {
    await open(tester, ReleaseDate.of(2019));
    await tester.tap(find.byKey(const ValueKey('release-date-pick-month')));
    await tester.pumpAndSettle();

    expect(find.text('2019'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('release-date-year--10')));
    await tester.tap(find.byKey(const ValueKey('release-date-year-1')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('release-date-year'))).data,
      '2010',
    );

    await tester.tap(find.byKey(const ValueKey('release-date-month-3')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, '2010-03');

    await tester.tap(save());
    await tester.pumpAndSettle();
    expect((result! as ReleaseDateSet).date, ReleaseDate.of(2010, 3));
  });

  testWidgets('the year alone can be chosen', (tester) async {
    await open(tester, null);
    await tester.tap(find.byKey(const ValueKey('release-date-pick-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('release-date-year-only')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field()).controller!.text, '2026');
  });

  testWidgets('removing detail asks first; keeping it changes nothing', (
    tester,
  ) async {
    await open(tester, ReleaseDate.of(2019, 3, 15));
    await tester.enterText(field(), '2019');
    await tester.tap(save());
    await tester.pumpAndSettle();

    expect(find.text('Use a less exact date?'), findsOneWidget);
    expect(
      find.text(
        'The saved date is March 15, 2019. Saving 2019 removes the day.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep the saved date'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    await tester.tap(save());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('release-date-confirm-less-precise')),
    );
    await tester.pumpAndSettle();
    expect((result! as ReleaseDateSet).date, ReleaseDate.of(2019));
  });

  testWidgets('an empty field clears the date', (tester) async {
    await open(tester, ReleaseDate.of(2019, 3));
    await tester.enterText(field(), '');
    await tester.pump();
    expect(preview(tester), 'Saving removes the release date.');

    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(result, isA<ReleaseDateCleared>());
  });

  testWidgets('the calendar opens on the saved day', (tester) async {
    await open(tester, ReleaseDate.of(2019, 3, 15));
    await tester.tap(find.byKey(const ValueKey('release-date-pick-day')));
    await tester.pumpAndSettle();

    expect(find.text('March 2019'), findsOneWidget);
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field()).controller!.text, '2019-03-20');
  });

  testWidgets('fits 320dp at 2x text without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await open(tester, ReleaseDate.of(2019, 3));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('release-date-pick-month')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
