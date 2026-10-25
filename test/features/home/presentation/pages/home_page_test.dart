import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/home/application/models/home_popular_track.dart';
import 'package:sonus_next/features/home/application/models/home_snapshot.dart';
import 'package:sonus_next/features/home/application/models/home_top_artist.dart';
import 'package:sonus_next/features/home/application/services/home_data_service.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';
import 'package:sonus_next/features/home/presentation/pages/home_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  testWidgets('renders populated Home sections', (tester) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(tester, controller);

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(find.text('Top Artists'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
    expect(find.text('New Albums'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-top-artist-artist_1')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-recent-track-song_recent')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-new-album-album_1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'popular track tap opens context instead of immediately playing',
    (tester) async {
      final controller = await _loadedController(_snapshot());

      await _pumpHome(tester, controller);

      await tester.tap(
        find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      );

      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Add to playlist'), findsOneWidget);
      expect(find.text('Go to album'), findsOneWidget);
      expect(find.text('Go to artist'), findsOneWidget);
    },
  );

  testWidgets('blocked recently added track remains visible and disabled', (
    tester,
  ) async {
    final controller = await _loadedController(
      _snapshot(
        recentTrack: _track(
          id: 'song_blocked',
          title: 'Blocked Song',
          blocked: true,
        ),
      ),
    );

    await _pumpHome(tester, controller);

    final blockedTrack = find.byKey(
      const ValueKey<String>('home-recent-track-song_blocked'),
    );

    expect(blockedTrack, findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);

    await tester.tap(blockedTrack);
    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('renders empty state', (tester) async {
    final controller = await _loadedController(
      const HomeSnapshot(
        recentlyAddedTracks: [],
        recentlyAddedAlbums: [],
        weeklyPopularTracks: [],
        weeklyTopArtists: [],
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('Your Home is empty'), findsOneWidget);
  });

  testWidgets('Top Artists artwork prefers dedicated artwork', (tester) async {
    final controller = await _loadedController(
      _snapshot(
        artist: _artist(
          topArtistsArtworkPath: 'C:/Music/top-artists.jpg',
          headerArtworkPath: 'C:/Music/header.jpg',
        ),
      ),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-top-artist-artwork-artist_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('top-artists.jpg'),
    );
  });

  testWidgets('Top Artists artwork falls back to header artwork', (
    tester,
  ) async {
    final controller = await _loadedController(
      _snapshot(artist: _artist(headerArtworkPath: 'C:/Music/header-only.jpg')),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-top-artist-artwork-artist_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('header-only.jpg'),
    );
  });

  testWidgets('New Albums card uses album artwork path', (tester) async {
    final controller = await _loadedController(
      _snapshot(album: _album(artworkPath: 'C:/Music/album-cover.jpg')),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-new-album-artwork-album_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('album-cover.jpg'),
    );
  });
  testWidgets('shows loading state during initial load', (tester) async {
    final completer = Completer<HomeSnapshot>();

    final service = _FakeHomeDataService(pendingResult: completer.future);

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    final load = controller.load();

    await _pumpHome(tester, controller, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      const HomeSnapshot(
        recentlyAddedTracks: [],
        recentlyAddedAlbums: [],
        weeklyPopularTracks: [],
        weeklyTopArtists: [],
      ),
    );

    await load;
    await tester.pumpAndSettle();
  });

  testWidgets('shows initial error state and retries successfully', (
    tester,
  ) async {
    final service = _FakeHomeDataService(error: StateError('Home failed'));

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    await controller.load();
    await _pumpHome(tester, controller);

    expect(find.text('Home could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    service.error = null;
    service.snapshot = _snapshot();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(find.text('Home could not be loaded.'), findsNothing);
  });

  testWidgets('refresh failure preserves existing content and shows banner', (
    tester,
  ) async {
    final service = _FakeHomeDataService(snapshot: _snapshot());

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    await controller.load();

    service.error = StateError('Refresh failed');

    await controller.refresh();
    await _pumpHome(tester, controller);

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      findsOneWidget,
    );

    expect(find.text('Home could not refresh.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('Sonus themes', _themeTests);
  group('Top Artists cards', _topArtistCardTests);
  group('Rail layout and focus', _railLayoutTests);
}

void _railLayoutTests() {
  const popular = ValueKey<String>('home-popular-track-song_popular');
  const artist = ValueKey<String>('home-top-artist-artist_1');
  const recent = ValueKey<String>('home-recent-track-song_recent');
  const album = ValueKey<String>('home-new-album-album_1');

  double widthOf(WidgetTester tester, Key key) =>
      tester.getSize(find.byKey(key)).width;

  // Regression: the rails shared the page's PageStorage slot, so a rail
  // built after scrolling down restored the page's vertical offset as its
  // own horizontal one and opened part-way along.
  testWidgets('rails built after scrolling down start at their first card', (
    tester,
  ) async {
    final base = _snapshot();
    final controller = await _loadedController(
      HomeSnapshot(
        recentlyAddedTracks: base.recentlyAddedTracks,
        recentlyAddedAlbums: [
          for (var i = 1; i <= 6; i++)
            LibraryAlbum(
              albumId: 'album_$i',
              title: 'Album $i',
              artistId: 'artist_1',
              artistName: 'Artist 1',
              trackCount: 2,
              dateAdded: DateTime.utc(2026, 9, 28),
            ),
        ],
        weeklyPopularTracks: base.weeklyPopularTracks,
        weeklyTopArtists: base.weeklyTopArtists,
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 600);
    addTearDown(tester.view.reset);

    await _pumpHome(tester, controller, size: const Size(411, 600));

    // The New Albums rail is below the fold and not built yet.
    expect(find.byKey(album), findsNothing);

    final page = tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    page.position.jumpTo(page.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // Any album card locates the rail, even if it opened past the first.
    final albumCard = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('home-new-album-');
    });
    final rail = tester.state<ScrollableState>(
      find
          .ancestor(of: albumCard.first, matching: find.byType(Scrollable))
          .first,
    );
    expect(rail.position.axis, Axis.horizontal);
    expect(rail.position.pixels, 0);
  });

  testWidgets('featured cards lead and supporting rails share one size', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());

    for (final (width, featured, standard) in [
      (320.0, 150.0, 130.0),
      (411.0, 170.0, 142.8),
      (800.0, 220.0, 180.0),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1600);
      addTearDown(tester.view.reset);

      await _pumpHome(tester, controller, size: Size(width, 1600));

      final reason = 'screen $width';
      expect(widthOf(tester, popular), closeTo(featured, 0.01), reason: reason);
      expect(widthOf(tester, recent), closeTo(standard, 0.01), reason: reason);
      expect(widthOf(tester, album), widthOf(tester, recent), reason: reason);
      expect(
        widthOf(tester, popular),
        greaterThan(widthOf(tester, artist)),
        reason: reason,
      );
      expect(
        widthOf(tester, artist),
        greaterThan(widthOf(tester, recent)),
        reason: reason,
      );
    }
  });

  testWidgets('the featured section carries a caption', (tester) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(
      tester,
      controller,
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
    );

    expect(find.text('Your most-played tracks this week'), findsOneWidget);
  });

  testWidgets('secondary card lines use the theme secondary text colour', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());
    final theme = SonusThemeFactory.build(
      const SonusAppearanceSpec(themeId: SonusThemeId.neonMixtape),
    );
    final colors = theme.extension<SonusColors>()!;

    await _pumpHome(tester, controller, theme: theme);

    final streams = tester.widget<Text>(
      find.descendant(
        of: find.byKey(popular),
        matching: find.text('12 weekly streams'),
      ),
    );
    expect(streams.style!.color, colors.textSecondary);
    expect(
      streams.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    final title = tester.widget<Text>(
      find.descendant(
        of: find.byKey(popular),
        matching: find.text('Popular Song'),
      ),
    );
    expect(title.style!.color, colors.textPrimary);
  });

  testWidgets('a blocked track is labelled unavailable for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _loadedController(
      _snapshot(
        recentTrack: _track(
          id: 'song_blocked',
          title: 'Blocked Song',
          blocked: true,
        ),
      ),
    );

    await _pumpHome(tester, controller);

    // The card merges its children, so the state is part of its label.
    final label = tester
        .getSemantics(
          find.byKey(const ValueKey<String>('home-recent-track-song_blocked')),
        )
        .label;
    expect(label, startsWith('Unavailable'));
    expect(label, contains('Blocked Song'));
    semantics.dispose();
  });

  testWidgets('keyboard focus outlines a card in the theme focus colour', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
    final colors = theme.extension<SonusColors>()!;
    const ring = ValueKey<String>('home-card-focus-ring');

    // The card's own focus node, which InkWell places above its child.
    FocusNode cardFocus(Key card) => Focus.of(
      tester.element(
        find.descendant(of: find.byKey(card), matching: find.byType(Column)),
      ),
    );

    Future<void> tabUntil(bool Function() reached) async {
      for (var i = 0; i < 8 && !reached(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
    }

    await _pumpHome(tester, controller, theme: theme);

    expect(find.byKey(ring), findsNothing);

    await tabUntil(() => cardFocus(popular).hasPrimaryFocus);
    expect(cardFocus(popular).hasPrimaryFocus, isTrue);

    final focusRing = find.byKey(ring);
    expect(focusRing, findsOneWidget);
    expect(
      find.descendant(of: focusRing, matching: find.byKey(popular)),
      findsOneWidget,
    );
    final border =
        (tester.widget<DecoratedBox>(focusRing).decoration as BoxDecoration)
                .border!
            as Border;
    expect(border.top.color, colors.focus);

    // Moving on hands the ring to the next card; only one card shows it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(cardFocus(popular).hasPrimaryFocus, isFalse);
    expect(find.byKey(ring), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(ring), matching: find.byKey(popular)),
      findsNothing,
    );
  });
}

void _topArtistCardTests() {
  const card = ValueKey<String>('home-top-artist-artist_1');

  Size artworkSize(WidgetTester tester) => tester.getSize(
    find.descendant(of: find.byKey(card), matching: find.byType(Stack)).first,
  );

  testWidgets('cards are portrait with artwork above an info panel', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(
      tester,
      controller,
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      size: const Size(411, 1600),
    );

    final cardSize = tester.getSize(find.byKey(card));
    final artwork = artworkSize(tester);

    expect(artwork.height / artwork.width, closeTo(4 / 3, 0.01));
    expect(cardSize.height, greaterThan(cardSize.width * 1.6));
    expect(artwork.width, closeTo(cardSize.width, 0.01));

    // The name and statistics sit below the artwork, not on it.
    final artworkBottom = tester
        .getBottomLeft(
          find
              .descendant(of: find.byKey(card), matching: find.byType(Stack))
              .first,
        )
        .dy;
    expect(
      tester.getTopLeft(find.text('Artist 1').last).dy,
      greaterThanOrEqualTo(artworkBottom),
    );
    expect(find.text('Rank 1', skipOffstage: false), findsNothing);
    expect(
      find.descendant(of: find.byKey(card), matching: find.text('#1')),
      findsOneWidget,
    );
  });

  testWidgets('card width adapts to the screen', (tester) async {
    final controller = await _loadedController(_snapshot());

    for (final (width, expected) in [
      (320.0, 140.0),
      (411.0, 158.67),
      (800.0, 190.0),
    ]) {
      // MediaQuery follows the view, not the test surface.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1600);
      addTearDown(tester.view.reset);

      await _pumpHome(tester, controller, size: Size(width, 1600));

      expect(
        tester.getSize(find.byKey(card)).width,
        closeTo(expected, 0.01),
        reason: 'screen $width',
      );
    }
  });

  testWidgets('portrait artwork crops with cover, keeping the upper part', (
    tester,
  ) async {
    final controller = await _loadedController(
      _snapshot(artist: _artist(topArtistsArtworkPath: 'C:/art/portrait.png')),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-top-artist-artwork-artist_1')),
    );
    expect(image.fit, BoxFit.cover);
    expect((image.alignment as Alignment).y, lessThan(0));
  });

  testWidgets('an artist without artwork shows their initials', (tester) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(tester, controller);

    final initials = find.descendant(
      of: find.byKey(card),
      matching: find.byKey(const ValueKey<String>('home-top-artist-initials')),
    );
    expect(initials, findsOneWidget);
    expect(
      find.descendant(of: initials, matching: find.text('A1')),
      findsOneWidget,
    );
  });

  testWidgets('long names wrap to two lines without overflow at 2x text', (
    tester,
  ) async {
    const name = 'The Extraordinarily Long Sample Collective';
    final controller = await _loadedController(
      _snapshot(
        artist: LibraryArtist(
          artistId: 'artist_1',
          name: name,
          albumCount: 1,
          songCount: 2,
          dateAdded: DateTime.utc(2026, 9, 28),
        ),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 2400);
    addTearDown(tester.view.reset);

    await _pumpHome(
      tester,
      controller,
      size: const Size(320, 2400),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(
      find.descendant(of: find.byKey(card), matching: find.text(name)),
    );
    expect(nameText.maxLines, 2);
  });

  testWidgets('tapping a card still opens the artist', (tester) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(tester, controller);
    await tester.tap(find.byKey(card));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ArtistProfilePage), findsOneWidget);
  });
}

void _themeTests() {
  for (final themeId in SonusThemeId.values) {
    testWidgets('renders every section in ${themeId.label} at 320px', (
      tester,
    ) async {
      final controller = await _loadedController(_snapshot());

      await _pumpHome(
        tester,
        controller,
        theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: themeId)),
        size: const Size(320, 1600),
      );

      expect(tester.takeException(), isNull);
      for (final title in [
        'Popular This Week',
        'Top Artists',
        'Recently Added',
        'New Albums',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
        findsOneWidget,
      );
    });
  }

  testWidgets('track sheet separates artist and album with a middle dot', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(tester, controller);
    await tester.tap(
      find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Artist 1 · Album 1'), findsOneWidget);
  });

  testWidgets('rails grow with large text instead of overflowing', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 2400);
    addTearDown(tester.view.reset);

    await _pumpHome(
      tester,
      controller,
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      size: const Size(320, 2400),
      textScale: 2,
    );

    // Portrait artist cards keep their minimum width on a narrow screen.
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('home-top-artist-artist_1')),
          )
          .width,
      140,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Popular Song'), findsOneWidget);
    expect(find.text('12 weekly streams'), findsWidgets);
  });

  testWidgets('section headings are announced as headings', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await _loadedController(_snapshot());

    await _pumpHome(
      tester,
      controller,
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
    );

    expect(
      tester.getSemantics(find.text('Top Artists')),
      matchesSemantics(label: 'Top Artists', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('rank badges use the theme accent and read as a rank', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _loadedController(_snapshot());
    final theme = SonusThemeFactory.build(
      const SonusAppearanceSpec(themeId: SonusThemeId.kickflip),
    );
    final colors = theme.extension<SonusColors>()!;

    await _pumpHome(tester, controller, theme: theme);

    final badge = find.text('#1').first;
    final label = tester.getSemantics(badge).label;
    expect(label, contains('Rank 1'));
    expect(label, isNot(contains('#1')));
    expect(tester.widget<Text>(badge).style!.color, colors.onAccentPrimary);
    final decorated = tester.widget<DecoratedBox>(
      find.ancestor(of: badge, matching: find.byType(DecoratedBox)).first,
    );
    expect((decorated.decoration as BoxDecoration).color, colors.accentPrimary);
    semantics.dispose();
  });

  testWidgets('decoration Off removes heading marks but keeps content', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(
      tester,
      controller,
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
    expect(find.text('Popular This Week'), findsOneWidget);
  });

  testWidgets('Concrete & Spray marks headings and textures the lead section', (
    tester,
  ) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(
      tester,
      controller,
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
    );

    expect(
      find.byKey(const ValueKey<String>('sonus-motif-mark')),
      findsNWidgets(4),
    );
    expect(
      find.byKey(const ValueKey<String>('sonus-surface-texture')),
      findsOneWidget,
    );
  });
}

Future<HomeController> _loadedController(HomeSnapshot snapshot) async {
  final controller = HomeController(
    service: _FakeHomeDataService(snapshot: snapshot),
    now: () => DateTime(2026, 9, 28, 12),
  );

  await controller.load();

  return controller;
}

Future<void> _pumpHome(
  WidgetTester tester,
  HomeController controller, {
  bool settle = true,
  ThemeData? theme,
  Size size = const Size(800, 1600),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);

  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<HomeController?>.value(
      value: controller,
      child: MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: const Scaffold(body: HomePage()),
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

HomeSnapshot _snapshot({
  LibraryTrack? recentTrack,
  LibraryArtist? artist,
  LibraryAlbum? album,
}) {
  final popularTrack = _track(id: 'song_popular', title: 'Popular Song');

  final resolvedRecentTrack =
      recentTrack ?? _track(id: 'song_recent', title: 'Recent Song');

  final resolvedArtist = artist ?? _artist();
  final resolvedAlbum = album ?? _album();

  return HomeSnapshot(
    recentlyAddedTracks: [resolvedRecentTrack],
    recentlyAddedAlbums: [resolvedAlbum],
    weeklyPopularTracks: [
      HomePopularTrack(track: popularTrack, rank: 1, qualifiedStreamCount: 12),
    ],
    weeklyTopArtists: [
      HomeTopArtist(
        artist: resolvedArtist,
        rank: 1,
        qualifiedStreamCount: 12,
        weeklyListeningDuration: const Duration(hours: 2, minutes: 15),
      ),
    ],
  );
}

LibraryTrack _track({
  required String id,
  required String title,
  bool blocked = false,
}) {
  return LibraryTrack(
    songId: id,
    title: title,
    artistId: 'artist_1',
    artistName: 'Artist 1',
    albumId: 'album_1',
    albumTitle: 'Album 1',
    albumEditionId: 'edition_1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 28),
    isAvailable: true,
    isSongBlocked: blocked,
    filePath: 'C:/Music/$id.mp3',
  );
}

LibraryArtist _artist({
  String? topArtistsArtworkPath,
  String? headerArtworkPath,
}) {
  return LibraryArtist(
    artistId: 'artist_1',
    name: 'Artist 1',
    albumCount: 1,
    songCount: 2,
    dateAdded: DateTime.utc(2026, 9, 28),
    topArtistsArtworkPath: topArtistsArtworkPath,
    headerArtworkPath: headerArtworkPath,
  );
}

LibraryAlbum _album({String? artworkPath}) {
  return LibraryAlbum(
    albumId: 'album_1',
    title: 'Album 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    trackCount: 2,
    dateAdded: DateTime.utc(2026, 9, 28),
    artworkPath: artworkPath,
  );
}

class _FakeHomeDataService implements HomeDataService {
  _FakeHomeDataService({HomeSnapshot? snapshot, this.error, this.pendingResult})
    : snapshot =
          snapshot ??
          const HomeSnapshot(
            recentlyAddedTracks: [],
            recentlyAddedAlbums: [],
            weeklyPopularTracks: [],
            weeklyTopArtists: [],
          );

  HomeSnapshot snapshot;
  Object? error;
  Future<HomeSnapshot>? pendingResult;

  int callCount = 0;

  @override
  int get sectionLimit => 6;

  @override
  Future<HomeSnapshot> load({required DateTime referenceLocal}) async {
    callCount++;

    final pendingResult = this.pendingResult;

    if (pendingResult != null) {
      return pendingResult;
    }

    final error = this.error;

    if (error != null) {
      throw error;
    }

    return snapshot;
  }
}
