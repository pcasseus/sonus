import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';

import '../widgets/film_reel/film_reel_harness.dart';
import 'library_page_test.dart' as base;

// SN-48H: the artist Film Reel's presentation (retired from the Library in
// App Update 1.1; kept for the future Sonus Wrapped). Fictional fixtures.
void main() {
  List<LibraryArtist> artists() => [
    base.createArtist(
      artistId: 'artist-1',
      name: 'The Extraordinarily Long Fixture Ensemble',
      albumCount: 12,
      songCount: 148,
    ),
    base.createArtist(artistId: 'artist-2', name: 'Nova', songCount: 3),
    LibraryArtist(
      artistId: 'artist-3',
      name: 'Pictured Fixture',
      albumCount: 1,
      songCount: 9,
      dateAdded: DateTime(2026),
      headerArtworkPath: '/art/portrait.png',
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) => pumpFilmReel(
    tester,
    artists: artists(),
    spec: spec,
    size: size,
    textScale: textScale,
  );

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
      await pump(
        tester,
        spec: SonusAppearanceSpec(themeId: id),
        size: const Size(320, 2000),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(byKey('film-reel-stats-below'), findsOneWidget);
    });
  }

  for (final level in SonusDecorationIntensity.values) {
    testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
      await pump(tester, spec: SonusAppearanceSpec(decoration: level));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('on a phone the panels sit beside the portrait, tilted', (
    tester,
  ) async {
    await pump(tester);

    expect(byKey('film-reel-panel-left'), findsOneWidget);
    expect(byKey('film-reel-panel-right'), findsOneWidget);
    expect(byKey('film-reel-stats-below'), findsNothing);
    expect(byKey('sonus-perspective-panel-transform'), findsNWidgets(2));

    final card = tester.getRect(byKey('artist-artist-1'));
    final left = tester.getRect(byKey('film-reel-panel-left'));
    final right = tester.getRect(byKey('film-reel-panel-right'));
    expect(left.center.dx, lessThan(card.left + 20));
    expect(right.center.dx, greaterThan(card.right - 20));
    expect(left.left, greaterThanOrEqualTo(0));
    expect(right.right, lessThanOrEqualTo(411));
  });

  testWidgets('wide screens keep the panels beside the portrait', (
    tester,
  ) async {
    await pump(tester, size: const Size(1280, 900));

    expect(tester.takeException(), isNull);
    expect(byKey('film-reel-stats-below'), findsNothing);
  });

  testWidgets('narrow screens put the statistics under the reel', (
    tester,
  ) async {
    await pump(tester, size: const Size(340, 760));

    expect(tester.takeException(), isNull);
    expect(byKey('film-reel-stats-below'), findsOneWidget);
    expect(byKey('sonus-perspective-panel-transform'), findsNothing);
  });

  for (final (name, spec) in const [
    ('High contrast', SonusAppearanceSpec(highContrast: true)),
    ('Low effects', SonusAppearanceSpec(lowEffects: true)),
  ]) {
    testWidgets('$name: the panels stay flat', (tester) async {
      await pump(tester, spec: spec);

      expect(tester.takeException(), isNull);
      expect(byKey('sonus-perspective-panel-transform'), findsNothing);
    });
  }

  testWidgets('dark and cinematic in Daylight too (D3)', (tester) async {
    await pump(
      tester,
      spec: const SonusAppearanceSpec(themeId: SonusThemeId.daylight),
    );

    final colours =
        tester
                .widget<DecoratedBox>(byKey('sonus-artwork-backdrop-colours'))
                .decoration
            as BoxDecoration;
    final top = (colours.gradient! as LinearGradient).colors.first;
    expect(top.computeLuminance(), lessThan(0.05));
  });

  testWidgets('with reduced motion a chevron moves at once', (tester) async {
    await pump(tester, spec: const SonusAppearanceSpec(reduceMotion: true));

    await tester.tap(byKey('film-reel-next'));
    await tester.pump();

    final pages = tester.widget<PageView>(byKey('film-reel-pages'));
    expect(pages.controller!.page, 1);
  });

  testWidgets('names wrap to two lines instead of truncating at once', (
    tester,
  ) async {
    await pump(tester);

    final name = tester.widget<Text>(
      find.text('The Extraordinarily Long Fixture Ensemble'),
    );
    expect(name.maxLines, 2);
  });

  testWidgets('portraits are decoded at the card size', (tester) async {
    await pump(tester);
    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(byKey('film-reel-portrait-artist-3'));
    expect(image.image, isA<ResizeImage>());
    final card = tester.getSize(byKey('artist-artist-3'));
    expect(
      (image.image as ResizeImage).width,
      lessThanOrEqualTo((card.width * 3).ceil()),
    );
  });
}
