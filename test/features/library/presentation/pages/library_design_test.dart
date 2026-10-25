import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';

import 'library_page_test.dart' as base;

// SN-48H: Artists Library presentation. Fictional fixtures only.
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
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Provider<LibraryQueryRepository?>.value(
        value: base.FakeLibraryQueryRepository(artists: artists()),
        child: MaterialApp(
          theme: SonusThemeFactory.build(spec),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  int columns(WidgetTester tester) {
    final grid = tester.widget<SliverGrid>(
      find.byKey(const PageStorageKey<String>('artists-grid')),
    );
    return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .crossAxisCount;
  }

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
      await pump(
        tester,
        spec: SonusAppearanceSpec(themeId: id),
        size: const Size(320, 2000),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(columns(tester), 2);
    });
  }

  for (final level in SonusDecorationIntensity.values) {
    testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
      await pump(tester, spec: SonusAppearanceSpec(decoration: level));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phones keep two columns; wide screens add columns', (
    tester,
  ) async {
    await pump(tester);
    expect(columns(tester), 2);

    await pump(tester, size: const Size(1280, 900));
    expect(columns(tester), 4);
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

  testWidgets('artwork is decoded at the card size', (tester) async {
    await pump(tester);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, lessThanOrEqualTo(411 * 3));
  });
}
