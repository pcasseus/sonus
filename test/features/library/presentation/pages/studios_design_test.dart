import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_form_section.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_studio_page.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';

import 'artist_studio_page_test.dart' as artist_base;

// SN-48K2: Track Studio and Artist Studio presentation. Fictional data.
void main() {
  LibraryTrack track() => LibraryTrack(
    songId: 'song-1',
    title: 'An Exceptionally Long Fixture Song Title That Has To Wrap',
    artistId: 'artist-1',
    artistName: 'The Extraordinarily Long Fixture Ensemble',
    albumId: 'album-1',
    albumTitle: 'Fixture Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 3,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026),
    isAvailable: true,
  );

  Widget themed(Widget home, SonusAppearanceSpec spec, double textScale) =>
      MaterialApp(
        theme: SonusThemeFactory.build(spec),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      );

  Future<void> pumpTrackStudio(
    WidgetTester tester, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      themed(
        TrackStudioPage(
          track: track(),
          albums: [
            LibraryAlbum(
              albumId: 'album-1',
              title: 'Fixture Album',
              artistId: 'artist-1',
              artistName: 'Fixture Artist',
              trackCount: 3,
              dateAdded: DateTime(2026),
              primaryEditionId: 'edition-1',
            ),
          ],
        ),
        spec,
        textScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<ArtistProfileController> pumpArtistStudio(
    WidgetTester tester, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = artist_base.FakeLibraryQueryRepository(
      artist: artist_base.createArtist(
        name: 'The Extraordinarily Long Fixture Ensemble',
      ),
    );
    final controller = ArtistProfileController(
      repository: repository,
      artistId: 'artist-1',
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      themed(
        ArtistStudioPage(
          controller: controller,
          repository: repository,
          userId: null,
        ),
        spec,
        textScale,
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('Track Studio', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pumpTrackStudio(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 4000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        // Track and disc numbers stack instead of squeezing side by side.
        final track = tester.getRect(
          find.byKey(const ValueKey<String>('track-number-field')),
        );
        final disc = tester.getRect(
          find.byKey(const ValueKey<String>('track-disc-number-field')),
        );
        expect(disc.top, greaterThan(track.bottom));
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        await pumpTrackStudio(
          tester,
          spec: SonusAppearanceSpec(decoration: level),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('groups fields into titled sections', (tester) async {
      await pumpTrackStudio(tester, size: const Size(411, 3000));

      for (final title in [
        'Metadata and artwork',
        'Details',
        'Version',
        'Credits',
      ]) {
        expect(
          find.widgetWithText(SonusFormSection, title),
          findsOneWidget,
          reason: title,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('track-studio-save-button')),
        findsOneWidget,
      );
    });
  });

  group('Artist Studio', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pumpArtistStudio(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 4000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            const ValueKey<String>('artist-studio-relationship-summary'),
          ),
          findsOneWidget,
        );
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        await pumpArtistStudio(
          tester,
          spec: SonusAppearanceSpec(decoration: level),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
