import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

import 'album_profile_page_test.dart' as base;

// SN-48J J6: Album Profile atmosphere, edition switching and track list.
void main() {
  const red = SonusArtworkColors(
    accent: Color(0xFFFF8A80),
    container: Color(0xFF8C1D18),
  );
  const blue = SonusArtworkColors(
    accent: Color(0xFF82B1FF),
    container: Color(0xFF0D47A1),
  );

  LibraryTrack track(
    String id, {
    required String edition,
    int number = 1,
    int disc = 1,
    String? title,
  }) => base.createTrack(
    songId: id,
    title: title ?? 'Song $id',
    albumEditionId: edition,
    albumEditionTitle: edition == 'edition-deluxe' ? 'Deluxe' : 'Standard',
    albumEditionType: edition == 'edition-deluxe'
        ? AlbumEditionType.deluxe
        : AlbumEditionType.standard,
    trackNumber: number,
    discNumber: disc,
  );

  LibraryAlbumEdition edition(
    String id,
    String title,
    AlbumEditionType type, {
    bool primary = false,
    String? artworkPath,
  }) => base.createLibraryEdition(
    editionId: id,
    title: title,
    type: type,
    isPrimary: primary,
    artworkPath: artworkPath,
  );

  /// Standard (red artwork) and Deluxe (blue artwork, two bonus tracks).
  base.FakeEditionAwareLibraryQueryRepository standardAndDeluxe() =>
      base.FakeEditionAwareLibraryQueryRepository(
        album: base.createAlbum(
          title: 'Concept Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
        ),
        editions: [
          edition(
            'edition-standard',
            'Standard',
            AlbumEditionType.standard,
            primary: true,
            artworkPath: '/art/standard.png',
          ),
          edition(
            'edition-deluxe',
            'Deluxe',
            AlbumEditionType.deluxe,
            artworkPath: '/art/deluxe.png',
          ),
        ],
        editionTracks: {
          'edition-standard': [
            track('s1', edition: 'edition-standard', number: 1),
            track('s2', edition: 'edition-standard', number: 2),
          ],
          'edition-deluxe': [
            track('s1', edition: 'edition-deluxe', number: 1),
            track('s2', edition: 'edition-deluxe', number: 2),
            track('d3', edition: 'edition-deluxe', number: 3, title: 'Bonus'),
          ],
        },
      );

  Future<_FakePalette> pump(
    WidgetTester tester, {
    base.FakeEditionAwareLibraryQueryRepository? repository,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    Map<String?, SonusArtworkColors?>? colours,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final palette = _FakePalette(
      colours ??
          {'/art/standard.png': red, '/art/deluxe.png': blue, null: null},
    );

    await tester.pumpWidget(
      base.buildSubject(
        repository: repository ?? standardAndDeluxe(),
        theme: SonusThemeFactory.build(spec),
        artworkPalette: palette,
        appBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: padding,
          ),
          child: child!,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return palette;
  }

  (SonusColors, SonusDecorationTokens) tokensFor(SonusAppearanceSpec spec) {
    final theme = SonusThemeFactory.build(spec);
    return (
      theme.extension<SonusColors>()!,
      theme.extension<SonusDecorationTokens>()!,
    );
  }

  Color pageBackground(WidgetTester tester) => tester
      .widget<Scaffold>(
        find.byKey(const ValueKey<String>('album-profile-page')),
      )
      .backgroundColor!;

  Color tracksSurface(WidgetTester tester) => tester
      .widget<Material>(
        find.byKey(const ValueKey<String>('album-profile-tracks-section')),
      )
      .color!;

  group('atmosphere', () {
    testWidgets('theme colours show first, then the artwork tints the page '
        'and the track list', (tester) async {
      const spec = SonusAppearanceSpec();
      final (colors, decoration) = tokensFor(spec);
      final tinted = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: red,
      );

      await pump(tester, settle: false);
      // Data loads, but artwork colours are not applied yet.
      await tester.pump();
      expect(pageBackground(tester), colors.background);

      await tester.pumpAndSettle();
      expect(pageBackground(tester), tinted.background);
      expect(tracksSurface(tester), tinted.surface);
      expect(tinted.isTinted, isTrue);
    });

    for (final (label, spec) in [
      (
        'Decoration Off',
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
      (
        'High contrast',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          highContrast: true,
        ),
      ),
      (
        'Low effects',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          lowEffects: true,
        ),
      ),
    ]) {
      testWidgets('$label keeps the theme colours', (tester) async {
        final (colors, _) = tokensFor(spec);
        await pump(tester, spec: spec);

        expect(pageBackground(tester), colors.background);
        expect(tracksSurface(tester), colors.surface);
      });
    }

    testWidgets('colours ease in, and jump with reduced motion', (
      tester,
    ) async {
      // Standard motion: one frame after the colours arrive, the page is
      // part-way between theme and artwork.
      await pump(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final (colors, decoration) = tokensFor(const SonusAppearanceSpec());
      final end = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: red,
      ).background;
      final mid = pageBackground(tester);
      expect(mid, isNot(colors.background));
      expect(mid, isNot(end));
      await tester.pumpAndSettle();

      // Reduced motion: straight to the final colour.
      const reduced = SonusAppearanceSpec(reduceMotion: true);
      await pump(tester, spec: reduced, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final (rc, rd) = tokensFor(reduced);
      expect(
        pageBackground(tester),
        SonusArtworkAtmosphere.resolve(
          colors: rc,
          decoration: rd,
          artwork: red,
        ).background,
      );
    });

    testWidgets('missing or colourless artwork falls back to the theme', (
      tester,
    ) async {
      final (colors, _) = tokensFor(const SonusAppearanceSpec());
      await pump(
        tester,
        // The palette reports no colour, as for missing, corrupt or
        // greyscale artwork.
        colours: const {},
      );

      expect(pageBackground(tester), colors.background);
      expect(tracksSurface(tester), colors.surface);
    });

    testWidgets('artwork is decoded at display size', (tester) async {
      await pump(tester);

      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<ResizeImage>());
      final width = (image.image as ResizeImage).width!;
      expect(width, lessThanOrEqualTo(264 * 3));
    });
  });

  group('editions', () {
    testWidgets('switching to Deluxe shows its tracks, count and colours', (
      tester,
    ) async {
      final palette = await pump(tester);
      final (colors, decoration) = tokensFor(const SonusAppearanceSpec());

      expect(find.text('Bonus'), findsNothing);
      expect(find.text('2 tracks • 6 min'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('album-profile-edition-segmented-button'),
          ),
          matching: find.text('Deluxe'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bonus'), findsOneWidget);
      expect(find.text('3 tracks • 9 min'), findsOneWidget);
      // Rows don't repeat the edition that is already on screen.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('album-track-d3')),
          matching: find.textContaining('Deluxe'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('album-profile-selected-edition-label'),
        ),
        findsOneWidget,
      );
      expect(palette.requested, contains('/art/deluxe.png'));
      expect(
        pageBackground(tester),
        SonusArtworkAtmosphere.resolve(
          colors: colors,
          decoration: decoration,
          artwork: blue,
        ).background,
      );
    });

    testWidgets('one edition shows no selector', (tester) async {
      await pump(
        tester,
        repository: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(primaryEditionId: 'edition-standard'),
          editions: [
            edition(
              'edition-standard',
              'Standard',
              AlbumEditionType.standard,
              primary: true,
            ),
          ],
          editionTracks: {
            'edition-standard': [track('s1', edition: 'edition-standard')],
          },
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('album-profile-edition-selector')),
        findsNothing,
      );
      expect(find.text('Deluxe'), findsNothing);
    });

    testWidgets('only the album\'s real editions are offered', (tester) async {
      await pump(
        tester,
        repository: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(primaryEditionId: 'edition-standard'),
          editions: [
            edition(
              'edition-standard',
              'Standard',
              AlbumEditionType.standard,
              primary: true,
            ),
            edition(
              'edition-anniversary',
              'Anniversary',
              AlbumEditionType.anniversary,
            ),
          ],
          editionTracks: {
            'edition-standard': [track('s1', edition: 'edition-standard')],
            'edition-anniversary': [
              track('s1', edition: 'edition-anniversary'),
            ],
          },
        ),
      );

      final selector = find.byKey(
        const ValueKey<String>('album-profile-edition-selector'),
      );
      expect(
        find.descendant(of: selector, matching: find.text('Standard')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: selector, matching: find.text('Anniversary')),
        findsOneWidget,
      );
      for (final absent in ['Deluxe', 'Expanded', 'Remaster']) {
        expect(
          find.descendant(of: selector, matching: find.text(absent)),
          findsNothing,
          reason: absent,
        );
      }
    });

    testWidgets('long edition titles wrap on small screens and still switch', (
      tester,
    ) async {
      const longTitle = 'Unless You Want It To Be (Extended Edition Version)';
      await pump(
        tester,
        size: const Size(320, 900),
        textScale: 2,
        repository: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(primaryEditionId: 'edition-standard'),
          editions: [
            edition(
              'edition-standard',
              'Standard',
              AlbumEditionType.standard,
              primary: true,
            ),
            edition('edition-long', longTitle, AlbumEditionType.other),
          ],
          editionTracks: {
            'edition-standard': [track('s1', edition: 'edition-standard')],
            'edition-long': [
              track('s1', edition: 'edition-long'),
              track('x2', edition: 'edition-long', number: 2, title: 'Extra'),
            ],
          },
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('album-profile-edition-choices')),
        findsOneWidget,
      );
      final rect = tester.getRect(find.text(longTitle));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      // Regression (J6 QA): chips force one line, which clipped the title.
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(longTitle))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);

      final choice = find.byKey(
        const ValueKey<String>('album-profile-edition-choice-edition-long'),
      );
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Extra'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('album-profile-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Extra'), findsOneWidget);
    });
  });

  group('track list', () {
    testWidgets('multi-disc editions get disc headings in the existing order', (
      tester,
    ) async {
      await pump(
        tester,
        repository: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(primaryEditionId: 'edition-standard'),
          editions: [
            edition(
              'edition-standard',
              'Standard',
              AlbumEditionType.standard,
              primary: true,
            ),
          ],
          editionTracks: {
            'edition-standard': [
              track('a', edition: 'edition-standard', number: 1, disc: 1),
              track('b', edition: 'edition-standard', number: 2, disc: 1),
              track('c', edition: 'edition-standard', number: 1, disc: 2),
            ],
          },
        ),
      );

      expect(find.text('Disc 1'), findsOneWidget);
      expect(find.text('Disc 2'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Disc 2')).dy,
        greaterThan(tester.getTopLeft(find.text('Song b')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Disc 2')).dy,
        lessThan(tester.getTopLeft(find.text('Song c')).dy),
      );
    });

    testWidgets('single-disc editions have no disc headings', (tester) async {
      await pump(tester);

      expect(find.textContaining('Disc '), findsNothing);
    });

    testWidgets('double-digit track numbers stay on one line at 2x text', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 8000),
        textScale: 2,
        repository: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(primaryEditionId: 'edition-standard'),
          editions: [
            edition(
              'edition-standard',
              'Standard',
              AlbumEditionType.standard,
              primary: true,
            ),
          ],
          editionTracks: {
            'edition-standard': [
              for (var n = 1; n <= 12; n++)
                track('t$n', edition: 'edition-standard', number: n),
            ],
          },
        ),
      );

      final number = find.descendant(
        of: find.byKey(const ValueKey<String>('album-track-t12')),
        matching: find.text('12'),
      );
      expect(number, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(number);
      final oneLine = TextPainter(
        text: paragraph.text,
        textScaler: paragraph.textScaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      expect(paragraph.size.height, lessThanOrEqualTo(oneLine.height + 0.5));
      oneLine.dispose();
    });

    // Regression (J6 QA): at 320dp and 2x text the number, duration and
    // menu left the title so little width that words broke apart.
    testWidgets('large text moves the duration to the credit line', (
      tester,
    ) async {
      await pump(tester, size: const Size(320, 4000), textScale: 2);

      final row = find.byKey(const ValueKey<String>('album-track-s1'));
      final duration = find.descendant(
        of: row,
        matching: find.textContaining('3:00'),
      );
      final title = find.descendant(of: row, matching: find.text('Song s1'));
      expect(duration, findsOneWidget);
      // Beneath the title, on the credit line, not beside it.
      expect(
        tester.getTopLeft(duration).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy - 1),
      );
      expect(
        tester.getSize(title).width,
        greaterThan(tester.getSize(row).width * 0.5),
      );
    });

    testWidgets('the list leaves room for anything anchored at the bottom', (
      tester,
    ) async {
      await pump(tester, padding: const EdgeInsets.only(bottom: 120));

      final list = tester.widget<ListView>(
        find.byKey(const PageStorageKey<String>('album-profile-scroll')),
      );
      expect((list.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(120));
    });
  });

  group('layout', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 4000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Concept Album'), findsWidgets);
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        await pump(tester, spec: SonusAppearanceSpec(decoration: level));

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide screens put the artwork beside the details', (
      tester,
    ) async {
      await pump(tester, size: const Size(800, 600));

      final artwork = tester.getRect(
        find.byKey(const ValueKey<String>('album-profile-artwork-album-1')),
      );
      final title = tester.getRect(
        find.byKey(const ValueKey<String>('album-profile-title-album-1')),
      );
      expect(title.left, greaterThan(artwork.right));
      // The first tracks are on screen.
      expect(find.text('Song s1').hitTestable(), findsOneWidget);
    });
  });
}

/// Returns fixed colours per artwork path, without reading files.
class _FakePalette extends SonusArtworkPalette {
  _FakePalette(this.colours);

  final Map<String?, SonusArtworkColors?> colours;
  final requested = <String?>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    requested.add(artworkPath);
    return colours[artworkPath];
  }
}
