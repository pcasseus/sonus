import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';

import 'artist_profile_page_test.dart' as base;

// SN-48I: Artist Profile hero, sections, collaborators and atmosphere.
// Fictional fixtures only.
void main() {
  const red = SonusArtworkColors(
    accent: Color(0xFFFF8A80),
    container: Color(0xFF8C1D18),
  );

  Future<_FakePalette> pump(
    WidgetTester tester, {
    required base.FakeLibraryQueryRepository repository,
    base.FakeQualifiedPlayRepository? plays,
    PlaybackCoordinator? playbackCoordinator,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
    Map<String?, SonusArtworkColors?>? colours,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final palette = _FakePalette(colours ?? {'/art/artist.png': red});

    await tester.pumpWidget(
      base.buildSubject(
        repository: repository,
        qualifiedPlays: plays,
        playbackCoordinator: playbackCoordinator,
        theme: SonusThemeFactory.build(spec),
        appBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ArtistProfilePage(
          artistId: 'artist-1',
          initialArtistName: 'Test Artist',
          artworkPalette: palette,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return palette;
  }

  /// Seven songs on the artist's own album; [streams] per song.
  (base.FakeLibraryQueryRepository, base.FakeQualifiedPlayRepository) catalogue(
    Map<String, int> streams, {
    List<LibraryTrack> extraTracks = const [],
    String? headerArtworkPath = '/art/artist.png',
    String? portraitPath,
  }) {
    final tracks = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
        base.createTrack(songId: id, title: 'Song $id'),
    ];
    final repository = base.FakeLibraryQueryRepository(
      artist: base.createArtist(
        headerArtworkPath: headerArtworkPath,
        topArtistsArtworkPath: portraitPath,
      ),
      albums: [base.createAlbum()],
      tracks: [...tracks, ...extraTracks],
    );
    final plays = base.FakeQualifiedPlayRepository([
      for (final MapEntry(key: id, value: count) in streams.entries)
        for (var i = 0; i < count; i++)
          base.qualifiedPlay(id, at: DateTime.utc(2026, 1, 1 + i)),
    ]);
    return (repository, plays);
  }

  Finder section(String key) => find.byKey(ValueKey<String>(key));

  (SonusColors, SonusDecorationTokens) tokensFor(SonusAppearanceSpec spec) {
    final theme = SonusThemeFactory.build(spec);
    return (
      theme.extension<SonusColors>()!,
      theme.extension<SonusDecorationTokens>()!,
    );
  }

  Color pageBackground(WidgetTester tester) => tester
      .widget<Scaffold>(
        find.byKey(const ValueKey<String>('artist-profile-page')),
      )
      .backgroundColor!;

  group('hero', () {
    // Regression: the album and song counts sat in an unconstrained Row and
    // overflowed the hero at 320dp with large text.
    testWidgets('fits 320dp at 2x text with long names and large counts', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 800),
        textScale: 2,
        repository: base.FakeLibraryQueryRepository(
          artist: base.createArtist(
            name: 'The Extraordinarily Long Fixture Ensemble',
            albumCount: 12,
            songCount: 148,
          ),
          tracks: [base.createTrack()],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('The Extraordinarily Long Fixture Ensemble'),
        findsWidgets,
      );
    });

    testWidgets('decodes the portrait and covers at display size', (
      tester,
    ) async {
      final (repository, plays) = catalogue({'a': 1});
      await pump(tester, repository: repository, plays: plays);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, isNotEmpty);
      final view = tester.view;
      final screenPixels = view.physicalSize.width;
      for (final image in images) {
        expect(image.image, isA<ResizeImage>());
        final banner =
            image.key ==
            const ValueKey<String>('artist-profile-banner-artist-1');
        // The full-width banner at the screen's width; everything else at
        // portrait or cover size.
        expect(
          (image.image as ResizeImage).width,
          lessThanOrEqualTo(banner ? screenPixels : 200 * 3),
        );
      }
    });

    group('SN-45 cinematic hero', () {
      Finder banner() =>
          find.byKey(const ValueKey<String>('artist-profile-banner-artist-1'));
      Finder portrait() =>
          find.byKey(const ValueKey<String>('artist-profile-artwork-artist-1'));
      Finder initials() =>
          find.byKey(const ValueKey<String>('artist-profile-artwork-fallback'));

      testWidgets('banner and portrait come from different saved images', (
        tester,
      ) async {
        final (repository, plays) = catalogue(
          {},
          headerArtworkPath: '/art/banner.png',
          portraitPath: '/art/portrait.png',
        );
        await pump(tester, repository: repository, plays: plays);

        final bannerImage = tester.widget<Image>(banner());
        final portraitImage = tester.widget<Image>(portrait());
        String fileOf(Image image) =>
            ((image.image as ResizeImage).imageProvider as FileImage).file.path;
        expect(fileOf(bannerImage), '/art/banner.png');
        expect(fileOf(portraitImage), '/art/portrait.png');
      });

      testWidgets('a banner alone never doubles as the portrait', (
        tester,
      ) async {
        final (repository, plays) = catalogue({});
        await pump(tester, repository: repository, plays: plays);

        expect(banner(), findsOneWidget);
        expect(portrait(), findsNothing);
        expect(initials(), findsOneWidget);
      });

      testWidgets('a portrait alone gets an atmosphere backdrop', (
        tester,
      ) async {
        final (repository, plays) = catalogue(
          {},
          headerArtworkPath: null,
          portraitPath: '/art/portrait.png',
        );
        await pump(tester, repository: repository, plays: plays);

        expect(banner(), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('artist-profile-banner-fallback')),
          findsOneWidget,
        );
        expect(portrait(), findsOneWidget);
      });

      testWidgets('the hero runs under a clear app bar to the screen top', (
        tester,
      ) async {
        final (repository, plays) = catalogue({});
        await pump(tester, repository: repository, plays: plays);

        expect(tester.getTopLeft(banner()).dy, 0);
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(
          appBar.backgroundColor is WidgetStateColor,
          isTrue,
          reason: 'clear at rest, solid only once scrolled under',
        );
      });

      testWidgets('the standing comes from all-time qualified streams', (
        tester,
      ) async {
        final (repository, plays) = catalogue({'a': 3, 'b': 2});
        await pump(tester, repository: repository, plays: plays);

        expect(
          find.text('#1 in your artists, all time · 5 streams'),
          findsOneWidget,
        );
      });

      testWidgets('no standing is invented without streams', (tester) async {
        final (repository, plays) = catalogue({});
        await pump(tester, repository: repository, plays: plays);

        expect(
          find.byKey(const ValueKey<String>('artist-profile-standing')),
          findsNothing,
        );
      });
    });

    testWidgets('an artist without a portrait shows their initials', (
      tester,
    ) async {
      final (repository, plays) = catalogue({}, headerArtworkPath: null);
      await pump(tester, repository: repository, plays: plays);

      expect(
        find.byKey(const ValueKey<String>('artist-profile-artwork-fallback')),
        findsOneWidget,
      );
      expect(find.text('TA'), findsOneWidget);
    });
  });

  group('SN-45 Top Tracks rows', () {
    testWidgets('streams and album, never the length', (tester) async {
      final (repository, plays) = catalogue({'a': 8, 'b': 7});
      await pump(tester, repository: repository, plays: plays);

      expect(find.text('8 streams • Test Album'), findsOneWidget);
      expect(find.text('7 streams • Test Album'), findsOneWidget);
      final row = find.byKey(const ValueKey<String>('artist-top-track-a'));
      expect(
        find.descendant(of: row, matching: find.text('3:00')),
        findsNothing,
      );
    });

    testWidgets('at most five, and never unstreamed songs', (tester) async {
      final (repository, plays) = catalogue({
        'a': 6,
        'b': 5,
        'c': 4,
        'd': 3,
        'e': 2,
        'f': 1,
      });
      await pump(tester, repository: repository, plays: plays);

      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        expect(
          find.byKey(ValueKey<String>('artist-top-track-$id')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('artist-top-track-f')), findsNothing);
      expect(find.byKey(const ValueKey('artist-top-track-g')), findsNothing);
    });
  });

  group('sections', () {
    testWidgets('Top Tracks, Albums and Collaborations come in that order, '
        'with no Songs section', (tester) async {
      final (repository, plays) = catalogue(
        {'a': 2, 'b': 1},
        extraTracks: [
          base.createTrack(
            songId: 'guest',
            title: 'Guest Verse',
            albumId: 'their-album',
            albumTitle: 'Their Album',
          ),
        ],
      );
      await pump(
        tester,
        size: const Size(411, 3000),
        repository: repository,
        plays: plays,
      );

      final top = tester.getTopLeft(section('artist-profile-top-tracks')).dy;
      final albums = tester.getTopLeft(section('artist-profile-albums')).dy;
      final collaborations = tester
          .getTopLeft(section('artist-profile-collaborations'))
          .dy;
      expect(top, lessThan(albums));
      expect(albums, lessThan(collaborations));
      expect(find.text('Songs'), findsNothing);
      expect(find.text('Guest Verse'), findsOneWidget);
    });

    testWidgets('a collaboration names the artist whose song it is', (
      tester,
    ) async {
      final (repository, plays) = catalogue(
        {},
        extraTracks: [
          base.createTrack(
            songId: 'their-song',
            title: 'Their Song',
            artistId: 'other-artist',
            artistName: 'Other Fixture',
            albumId: 'their-album',
            albumTitle: 'Their Album',
          ),
          base.createTrack(
            songId: 'soundtrack',
            title: 'Soundtrack Song',
            albumId: 'their-album',
            albumTitle: 'Their Album',
          ),
        ],
      );
      await pump(
        tester,
        size: const Size(411, 3000),
        repository: repository,
        plays: plays,
      );

      expect(find.text('Other Fixture • Their Album'), findsOneWidget);
      // Their own song on someone else's album repeats no name.
      expect(find.text('Their Album'), findsOneWidget);
    });

    testWidgets('Top Tracks shows the five most streamed with their counts', (
      tester,
    ) async {
      final (repository, plays) = catalogue({
        'a': 1,
        'b': 7,
        'c': 3,
        'd': 5,
        'e': 2,
        'f': 4,
      });
      await pump(
        tester,
        size: const Size(411, 3000),
        repository: repository,
        plays: plays,
      );

      final rows = tester
          .widgetList<ListTile>(
            find.descendant(
              of: section('artist-top-track-list'),
              matching: find.byType(ListTile),
            ),
          )
          .map((tile) => (tile.key! as ValueKey<String>).value)
          .toList();
      expect(rows, [
        'artist-top-track-b',
        'artist-top-track-d',
        'artist-top-track-f',
        'artist-top-track-c',
        'artist-top-track-e',
      ]);
      expect(find.text('7 streams • Test Album'), findsOneWidget);
      expect(find.text('2 streams • Test Album'), findsOneWidget);
      expect(find.text('Song a'), findsNothing);
    });

    testWidgets('Top Tracks is hidden until something has been streamed', (
      tester,
    ) async {
      final (repository, plays) = catalogue({});
      await pump(tester, repository: repository, plays: plays);

      expect(find.text('Top Tracks'), findsNothing);
      expect(section('artist-profile-albums'), findsOneWidget);
    });

    testWidgets('Top Tracks leaves out blacklisted songs', (tester) async {
      final (repository, plays) = catalogue(
        {'blocked': 9, 'a': 1},
        extraTracks: [
          base.createTrack(
            songId: 'blocked',
            title: 'Blocked Song',
            isSongBlocked: true,
          ),
        ],
      );
      await pump(tester, repository: repository, plays: plays);

      expect(
        find.byKey(const ValueKey('artist-top-track-blocked')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('artist-top-track-a')), findsOneWidget);
    });

    testWidgets('Top Tracks refreshes after returning from an album and on '
        'pull to refresh', (tester) async {
      final (repository, plays) = catalogue({'a': 1});
      await pump(tester, repository: repository, plays: plays);
      expect(find.byKey(const ValueKey('artist-top-track-b')), findsNothing);

      // Songs are played on the album page.
      plays.plays.addAll([base.qualifiedPlay('b'), base.qualifiedPlay('b')]);
      final album = find.byKey(const ValueKey<String>('artist-album-album-1'));
      await tester.ensureVisible(album);
      await tester.pumpAndSettle();
      await tester.tap(album);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('2 streams • Test Album'), findsOneWidget);

      plays.plays.addAll([for (var i = 0; i < 3; i++) base.qualifiedPlay('c')]);
      final scroll = find.byKey(
        const PageStorageKey<String>('artist-profile-scroll'),
      );
      // Back to the top, then pull down to refresh.
      await tester.drag(scroll, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('3 streams • Test Album'), findsOneWidget);
    });

    testWidgets('a Top Tracks song plays with Top Tracks as the queue', (
      tester,
    ) async {
      final (repository, plays) = catalogue({'a': 3, 'b': 2, 'c': 1});
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: repository,
        plays: plays,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-top-track-b')),
      );
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((t) => t.songId), ['a', 'b', 'c']);
      expect(engine.lastStartIndex, 1);
      await engine.dispose();
    });

    testWidgets('Play all queues the whole catalogue, not just Top Tracks', (
      tester,
    ) async {
      final (repository, plays) = catalogue({'a': 1});
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: repository,
        plays: plays,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-profile-play-all-button')),
      );
      await tester.pump();

      expect(engine.lastLoadedTracks, hasLength(7));
      await engine.dispose();
    });
  });

  group('project collaborators', () {
    /// A cast project that owns a soundtrack and performs none of it, as
    /// production stores it (structured credits, no main credit).
    base.FakeStructuredLibraryQueryRepository castProject({
      bool profileEligible = false,
      List<LibraryTrack>? tracks,
    }) {
      return base.FakeStructuredLibraryQueryRepository(
        artist: base.createArtist(name: 'Fixture Movie Cast', songCount: 0),
        profileEligible: profileEligible,
        albums: [base.createAlbum(title: 'Fixture Movie Soundtrack')],
        allTracks:
            tracks ??
            [
              base.createTrack(
                songId: 't1',
                title: 'Opening Number',
                artistId: 'lead',
                artistName: 'Fixture Lead',
              ),
              base.createTrack(
                songId: 't2',
                title: 'Duet Reprise',
                artistId: 'lead',
                artistName: 'Fixture Lead',
              ),
              base.createTrack(
                songId: 't3',
                title: 'Villain Song',
                artistId: 'rival',
                artistName: 'Fixture Rival',
              ),
              base.createTrack(
                songId: 'other',
                title: 'Elsewhere',
                artistId: 'rival',
                artistName: 'Fixture Rival',
                albumId: 'rival-album',
              ),
            ],
        artists: [
          base.createArtist(artistId: 'lead', name: 'Fixture Lead'),
          base.createArtist(artistId: 'rival', name: 'Fixture Rival'),
        ],
      );
    }

    testWidgets('a project that only owns albums opens, listing each '
        'performer once', (tester) async {
      await pump(
        tester,
        size: const Size(411, 2000),
        repository: castProject(),
      );

      expect(find.text('Artist not found'), findsNothing);
      expect(section('artist-profile-collaborators'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('artist-collaborator-lead')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('artist-collaborator-rival')),
        findsOneWidget,
      );
      expect(find.text('2 songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      // The project's own album is listed even though others perform it.
      expect(
        find.byKey(const ValueKey('artist-album-album-1')),
        findsOneWidget,
      );
    });

    testWidgets('an artist with neither credits nor albums is not found', (
      tester,
    ) async {
      await pump(
        tester,
        repository: base.FakeStructuredLibraryQueryRepository(
          artist: base.createArtist(),
          profileEligible: false,
        ),
      );

      expect(find.text('Artist not found'), findsOneWidget);
    });

    testWidgets('a performer opens their own profile', (tester) async {
      await pump(
        tester,
        size: const Size(411, 2000),
        repository: castProject(),
      );

      await tester.tap(find.byKey(const ValueKey('artist-collaborator-rival')));
      await tester.pumpAndSettle();

      final pages = tester
          .widgetList<ArtistProfilePage>(
            find.byType(ArtistProfilePage, skipOffstage: false),
          )
          .map((page) => page.artistId);
      expect(pages, ['artist-1', 'rival']);
    });

    testWidgets('play plays only that performer\'s songs on the project', (
      tester,
    ) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        size: const Size(411, 2000),
        repository: castProject(),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(
        find.byKey(const ValueKey('artist-collaborator-play-lead')),
      );
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        't1',
        't2',
      ]);
      await engine.dispose();
    });

    testWidgets('Play all on a project plays its soundtrack', (tester) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: castProject(),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-profile-play-all-button')),
      );
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        't1',
        't2',
        't3',
      ]);
      await engine.dispose();
    });

    testWidgets('no Collaborators section when the artist performs all of '
        'their albums', (tester) async {
      await pump(
        tester,
        repository: base.FakeStructuredLibraryQueryRepository(
          artist: base.createArtist(),
          albums: [base.createAlbum()],
          mainTracks: [base.createTrack()],
          allTracks: [base.createTrack()],
        ),
      );

      expect(find.text('Collaborators'), findsNothing);
      expect(find.text('Collaborations'), findsNothing);
    });
  });

  group('atmosphere', () {
    testWidgets('theme colours show first, then the artwork tints the page', (
      tester,
    ) async {
      final (colors, decoration) = tokensFor(const SonusAppearanceSpec());
      final (repository, plays) = catalogue({'a': 1});

      await pump(tester, repository: repository, plays: plays, settle: false);
      await tester.pump();
      expect(pageBackground(tester), colors.background);

      await tester.pumpAndSettle();
      expect(
        pageBackground(tester),
        SonusArtworkAtmosphere.resolve(
          colors: colors,
          decoration: decoration,
          artwork: red,
        ).background,
      );
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
        final (repository, plays) = catalogue({'a': 1});
        await pump(tester, repository: repository, plays: plays, spec: spec);

        expect(pageBackground(tester), colors.background);
      });
    }

    testWidgets('Subtle keeps the theme accent on Play all', (tester) async {
      const spec = SonusAppearanceSpec(
        decoration: SonusDecorationIntensity.subtle,
      );
      final (colors, _) = tokensFor(spec);
      final (repository, plays) = catalogue({'a': 1});
      await pump(tester, repository: repository, plays: plays, spec: spec);

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('artist-profile-play-all-button')),
      );
      expect(
        button.style!.backgroundColor!.resolve(const {}),
        colors.accentPrimary,
      );
    });

    testWidgets('reduced motion jumps straight to the artwork colours', (
      tester,
    ) async {
      const reduced = SonusAppearanceSpec(reduceMotion: true);
      final (colors, decoration) = tokensFor(reduced);
      final (repository, plays) = catalogue({'a': 1});
      await pump(
        tester,
        repository: repository,
        plays: plays,
        spec: reduced,
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        pageBackground(tester),
        SonusArtworkAtmosphere.resolve(
          colors: colors,
          decoration: decoration,
          artwork: red,
        ).background,
      );
    });

    testWidgets('artwork without colour falls back to the theme', (
      tester,
    ) async {
      final (colors, _) = tokensFor(const SonusAppearanceSpec());
      final (repository, plays) = catalogue({'a': 1});
      await pump(tester, repository: repository, plays: plays, colours: {});

      expect(pageBackground(tester), colors.background);
    });
  });

  group('layout', () {
    (base.FakeLibraryQueryRepository, base.FakeQualifiedPlayRepository)
    everySection() => catalogue(
      {'a': 3, 'b': 2},
      extraTracks: [
        base.createTrack(
          songId: 'guest',
          title: 'An Unusually Long Collaboration Title For Wrapping',
          albumId: 'their-album',
          albumTitle: 'Their Album With A Long Name',
        ),
      ],
    );

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        final (repository, plays) = everySection();
        await pump(
          tester,
          repository: repository,
          plays: plays,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 4000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Top Tracks'), findsOneWidget);
        expect(find.text('Collaborations'), findsOneWidget);
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        final (repository, plays) = everySection();
        await pump(
          tester,
          repository: repository,
          plays: plays,
          spec: SonusAppearanceSpec(decoration: level),
        );

        expect(tester.takeException(), isNull);
      });
    }

    // Regression (SN-48I emulator QA): at 320dp with 2x text the long
    // headings broke mid-word ("Collaborati / ons").
    testWidgets('section headings stay on one line at 320dp and 2x text', (
      tester,
    ) async {
      final (repository, plays) = everySection();
      await pump(
        tester,
        repository: repository,
        plays: plays,
        size: const Size(320, 4000),
        textScale: 2,
      );

      for (final heading in ['Top Tracks', 'Albums', 'Collaborations']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(heading),
        );
        final lines = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: heading.length),
            )
            .map((box) => box.top)
            .toSet();
        expect(lines, hasLength(1), reason: heading);
      }
    });

    testWidgets('wide screens put the portrait beside the name', (
      tester,
    ) async {
      final (repository, plays) = catalogue({
        'a': 1,
      }, portraitPath: '/art/portrait.png');
      await pump(
        tester,
        repository: repository,
        plays: plays,
        size: const Size(800, 600),
      );

      final portrait = tester.getRect(
        find.byKey(const ValueKey<String>('artist-profile-artwork-artist-1')),
      );
      final name = tester.getRect(
        find.byKey(const ValueKey<String>('artist-profile-name-artist-1')),
      );
      expect(name.left, greaterThan(portrait.right));
    });

    testWidgets('row controls keep 48dp touch targets', (tester) async {
      final (repository, plays) = everySection();
      await pump(tester, repository: repository, plays: plays);

      final menu = tester.getSize(
        find.byKey(const ValueKey<String>('artist-top-track-menu-a')),
      );
      expect(menu.width, greaterThanOrEqualTo(48));
      expect(menu.height, greaterThanOrEqualTo(48));
      final play = tester.getSize(
        find.byKey(const ValueKey<String>('artist-profile-play-all-button')),
      );
      expect(play.height, greaterThanOrEqualTo(48));
    });
  });
}

/// Returns fixed colours per artwork path, without reading files.
class _FakePalette extends SonusArtworkPalette {
  _FakePalette(this.colours);

  final Map<String?, SonusArtworkColors?> colours;

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    return colours[artworkPath];
  }
}
