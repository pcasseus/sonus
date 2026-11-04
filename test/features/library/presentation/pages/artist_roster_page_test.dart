// UI redesign L2: the Artist Roster, opened from the real Film Reel.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_roster_page.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';

import 'library_page_test.dart' as base;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

class _Stats implements ArtistLibraryStatisticsService {
  _Stats(this.artists, this.ranks);

  final List<LibraryArtist> artists;
  final Map<String, int> ranks;
  int loads = 0;

  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async {
    loads++;
    return ArtistLibraryStatisticsSnapshot([
      for (final artist in artists)
        ArtistLibraryStatistics(
          artist: artist,
          rank: ranks[artist.artistId],
          qualifiedStreams: ranks.containsKey(artist.artistId)
              ? 100 - ranks[artist.artistId]!
              : 0,
          listened: Duration(minutes: ranks[artist.artistId] ?? 0),
        ),
    ]);
  }
}

List<LibraryArtist> roster(int count) => [
  for (var i = 0; i < count; i++)
    base.createArtist(
      artistId: 'artist-$i',
      name: 'Artist ${String.fromCharCode(65 + i % 26)}${i ~/ 26}',
      albumCount: 1,
      songCount: 2,
    ),
];

void main() {
  final ada = base.createArtist(
    artistId: 'ada',
    name: 'Ada Lune',
    albumCount: 2,
    songCount: 18,
  );
  final ben = base.createArtist(artistId: 'ben', name: 'Ben Vale');
  final zed = base.createArtist(artistId: 'zed', name: 'Zed Night');
  final three = [ada, ben, zed];

  Future<_Stats> pump(
    WidgetTester tester, {
    List<LibraryArtist>? artists,
    Map<String, int> ranks = const {'ada': 1, 'zed': 2},
    Size size = const Size(393, 852),
    double textScale = 1,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  }) async {
    final list = artists ?? three;
    final stats = _Stats(list, ranks);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: base.FakeLibraryQueryRepository(artists: list),
          ),
          Provider<ArtistLibraryStatisticsService?>.value(value: stats),
        ],
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
    return stats;
  }

  Future<void> openRoster(WidgetTester tester) async {
    await tester.tap(byKey('library-roster-button'));
    await tester.pumpAndSettle();
    expect(byKey('artist-roster-page'), findsOneWidget);
  }

  String featuredName(WidgetTester tester) =>
      tester.widget<Text>(byKey('roster-featured-name')).data!;

  group('preview and choice', () {
    testWidgets('opens on the Film Reel\'s centred artist', (tester) async {
      await pump(tester);
      await tester.tap(byKey('film-reel-next'));
      await tester.pumpAndSettle();

      await openRoster(tester);

      expect(featuredName(tester), 'BEN VALE');
      expect(find.text('UNRANKED'), findsOneWidget);
    });

    testWidgets('tapping a portrait previews it and stays in the Roster', (
      tester,
    ) async {
      await pump(tester);
      await openRoster(tester);
      expect(featuredName(tester), 'ADA LUNE');
      expect(find.text('#1 ARTIST RANK'), findsOneWidget);

      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      expect(byKey('artist-roster-page'), findsOneWidget);
      expect(featuredName(tester), 'ZED NIGHT');
      expect(find.text('#2 ARTIST RANK'), findsOneWidget);
      final tile = tester.getSemantics(byKey('roster-tile-zed'));
      expect(tile.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('SELECT ARTIST closes it and centres the artist in the reel', (
      tester,
    ) async {
      final stats = await pump(tester);
      await openRoster(tester);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('roster-select'));
      await tester.pumpAndSettle();

      expect(byKey('artist-roster-page'), findsNothing);
      expect(find.text('#2'), findsOneWidget, reason: 'Zed is centred');
      expect(stats.loads, 1, reason: 'the Roster reads the same statistics');
    });

    testWidgets('Back closes it without choosing anyone', (tester) async {
      await pump(tester);
      await openRoster(tester);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('roster-back'));
      await tester.pumpAndSettle();

      expect(byKey('artist-roster-page'), findsNothing);
      expect(find.text('#1'), findsOneWidget, reason: 'Ada is still centred');
    });

    testWidgets('the search icon opens the Roster ready to type', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(byKey('roster-search'));
      expect(field.focusNode!.hasFocus, isTrue);
    });
  });

  group('finding artists', () {
    testWidgets('search narrows the grid and starts at the first page', (
      tester,
    ) async {
      await pump(tester);
      await openRoster(tester);

      await tester.enterText(byKey('roster-search'), 'vale');
      await tester.pumpAndSettle();

      expect(byKey('roster-tile-ben'), findsOneWidget);
      expect(byKey('roster-tile-ada'), findsNothing);
      expect(find.text('Page 1 of 1'), findsOneWidget);

      await tester.enterText(byKey('roster-search'), 'nobody');
      await tester.pumpAndSettle();
      expect(byKey('roster-no-results'), findsOneWidget);
    });

    testWidgets('sorting reorders the grid and is remembered', (tester) async {
      await pump(tester);
      await openRoster(tester);
      expect(find.text('Sort: Most Played'), findsOneWidget);

      double left(String id) => tester.getTopLeft(byKey('roster-tile-$id')).dx;
      // Most played: Ada (#1), Zed (#2), then unranked Ben.
      expect(left('ada'), lessThan(left('zed')));
      expect(left('zed'), lessThan(left('ben')));

      await tester.tap(byKey('roster-sort'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('roster-sort-name'));
      await tester.pumpAndSettle();
      expect(left('ben'), lessThan(left('zed')));

      await tester.tap(byKey('roster-back'));
      await tester.pumpAndSettle();
      await openRoster(tester);
      expect(find.text('Sort: Name'), findsOneWidget);
    });

    testWidgets('A-Z reaches a later letter\'s page', (tester) async {
      final artists = [
        for (var i = 0; i < 60; i++)
          base.createArtist(
            artistId: 'artist-$i',
            name: '${String.fromCharCode(65 + i ~/ 3)} Artist $i',
          ),
      ];
      await pump(tester, artists: artists, ranks: const {});
      await openRoster(tester);

      expect(find.text('Sort: Most Played'), findsOneWidget);
      await tester.tap(byKey('roster-az'));
      await tester.pumpAndSettle();
      // Names run from A to T: Z has nobody, so it cannot be chosen.
      expect(
        tester.widget<TextButton>(byKey('roster-letter-Z')).onPressed,
        isNull,
      );
      await tester.tap(byKey('roster-letter-M'));
      await tester.pumpAndSettle();

      // A-Z lists by name; M starts at the 37th artist (12 letters x 3),
      // on page 3 of 4.
      expect(find.text('Sort: Name'), findsOneWidget);
      expect(find.text('Page 3 of 4'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('roster-tile-artist-36')),
        findsOneWidget,
      );
    });
  });

  // Device QA (Galaxy S26 Ultra): with the keyboard open, the featured
  // artist, statistics and SELECT ARTIST used to keep their space and no
  // portrait was visible above the keyboard.
  group('searching with the keyboard open (S26 Ultra)', () {
    const dpr = 3.5;
    const screen = Size(412, 891);
    const keyboard = 350.0;

    Future<_Stats> pumpPhone(
      WidgetTester tester, {
      List<LibraryArtist>? artists,
      double textScale = 1,
      Size size = screen,
    }) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = size * dpr;
      tester.view.padding = const FakeViewPadding(
        top: 40 * dpr,
        bottom: 24 * dpr,
      );
      addTearDown(tester.view.reset);
      final list = artists ?? roster(60);
      final stats = _Stats(list, const {});
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LibraryQueryRepository?>.value(
              value: base.FakeLibraryQueryRepository(artists: list),
            ),
            Provider<ArtistLibraryStatisticsService?>.value(value: stats),
          ],
          child: MaterialApp(
            theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
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
      return stats;
    }

    Future<void> openKeyboard(WidgetTester tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * dpr);
      await tester.pumpAndSettle();
    }

    Future<void> closeKeyboard(WidgetTester tester) async {
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    }

    double keyboardTop(WidgetTester tester) =>
        tester.view.physicalSize.height / dpr - keyboard;

    Finder tiles() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('roster-tile-'),
    );

    int tilesAboveKeyboard(WidgetTester tester) =>
        tiles().evaluate().where((element) {
          final rect = tester.getRect(find.byWidget(element.widget));
          return rect.top >= 0 && rect.bottom <= keyboardTop(tester);
        }).length;

    testWidgets('the matches take the space above the keyboard', (
      tester,
    ) async {
      await pumpPhone(tester);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);

      expect(byKey('roster-search-results'), findsOneWidget);
      expect(byKey('roster-featured-portrait'), findsNothing);
      expect(byKey('roster-select'), findsNothing);
      final field = tester.getRect(byKey('roster-search'));
      expect(field.bottom, lessThan(keyboardTop(tester)));
      expect(tilesAboveKeyboard(tester), greaterThanOrEqualTo(15));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every match can be reached by scrolling', (tester) async {
      await pumpPhone(tester);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      await tester.enterText(byKey('roster-search'), 'artist');
      await tester.pumpAndSettle();
      expect(find.text('60 matches'), findsOneWidget);

      // The last match in name order is "Artist Z1" (artist-51).
      await tester.scrollUntilVisible(
        byKey('roster-tile-artist-51'),
        200,
        scrollable: find
            .descendant(
              of: byKey('roster-search-results'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(byKey('roster-tile-artist-51'));
      await tester.pumpAndSettle();
      final last = tester.getRect(byKey('roster-tile-artist-51'));
      expect(last.bottom, lessThanOrEqualTo(keyboardTop(tester) + 1));
    });

    testWidgets('one match, no match, and clearing the search', (tester) async {
      await pumpPhone(tester);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);

      await tester.enterText(byKey('roster-search'), 'artist q1');
      await tester.pumpAndSettle();
      expect(find.text('1 match'), findsOneWidget);
      expect(tiles(), findsOneWidget);

      await tester.enterText(byKey('roster-search'), 'nobody');
      await tester.pumpAndSettle();
      expect(byKey('roster-no-results'), findsOneWidget);
      expect(tiles(), findsNothing);

      await tester.tap(byKey('roster-search-clear'));
      await tester.pumpAndSettle();
      expect(find.text('60 artists'), findsOneWidget);
      expect(
        tester.widget<TextField>(byKey('roster-search')).focusNode!.hasFocus,
        isTrue,
        reason: 'clearing keeps typing possible',
      );
    });

    testWidgets('picking a match previews it and brings the Roster back', (
      tester,
    ) async {
      await pumpPhone(tester);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      await tester.enterText(byKey('roster-search'), 'artist q');
      await tester.pumpAndSettle();

      await tester.tap(byKey('roster-tile-artist-42'));
      await tester.pump();
      // The field let go of focus, so the keyboard closes.
      expect(
        tester.widget<TextField>(byKey('roster-search')).focusNode!.hasFocus,
        isFalse,
      );
      await closeKeyboard(tester);

      expect(featuredName(tester), 'ARTIST Q1');
      expect(byKey('roster-select'), findsOneWidget);
      expect(byKey('roster-tile-artist-42'), findsOneWidget);
      expect(
        tester.widget<TextField>(byKey('roster-search')).controller!.text,
        'artist q',
        reason: 'the search stays',
      );
    });

    testWidgets('closing the keyboard restores the full Roster, still '
        'filtered', (tester) async {
      await pumpPhone(tester);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      await tester.enterText(byKey('roster-search'), 'artist b');
      await tester.pumpAndSettle();

      await closeKeyboard(tester);

      expect(byKey('roster-search-results'), findsNothing);
      expect(byKey('roster-featured-portrait'), findsOneWidget);
      expect(byKey('roster-select'), findsOneWidget);
      expect(tiles(), findsNWidgets(3), reason: 'B0, B1, B2');
    });

    testWidgets('320dp with 2x text and the keyboard open', (tester) async {
      await pumpPhone(tester, size: const Size(320, 700), textScale: 2);
      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      await tester.enterText(byKey('roster-search'), 'artist');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final field = tester.getRect(byKey('roster-search'));
      expect(field.bottom, lessThan(keyboardTop(tester)));
      expect(tilesAboveKeyboard(tester), greaterThanOrEqualTo(1));
    });
  });

  group('large libraries', () {
    testWidgets('2,000 artists: one page of portraits is built at a time, '
        'and every page is reachable with buttons', (tester) async {
      final artists = roster(2000);
      final stats = await pump(tester, artists: artists, ranks: const {});
      await openRoster(tester);

      int builtTiles() => find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'roster-tile-',
                ),
          )
          .evaluate()
          .length;

      expect(find.text('Page 1 of 134'), findsOneWidget);
      expect(builtTiles(), lessThanOrEqualTo(15));

      for (var i = 0; i < 3; i++) {
        await tester.tap(byKey('roster-page-next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Page 4 of 134'), findsOneWidget);
      expect(builtTiles(), lessThanOrEqualTo(30));

      await tester.tap(byKey('roster-page-previous'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 134'), findsOneWidget);
      expect(stats.loads, 1, reason: 'no statistics read while browsing');
      expect(tester.takeException(), isNull);
    });
  });

  group('layout and accessibility', () {
    testWidgets('typical phone: five portraits a row, three rows', (
      tester,
    ) async {
      await pump(tester, artists: roster(40), ranks: const {});
      await openRoster(tester);

      final tiles = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('roster-tile-'),
      );
      final rects = [
        for (final tile in tiles.evaluate())
          tester.getRect(find.byWidget(tile.widget)),
      ];
      expect(rects, hasLength(15));
      expect({for (final r in rects) r.left.round()}, hasLength(5));
      expect({for (final r in rects) r.top.round()}, hasLength(3));
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label}: fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 700),
          textScale: 2,
        );
        await openRoster(tester);

        expect(tester.takeException(), isNull);
        expect(byKey('roster-compact'), findsOneWidget);
        expect(byKey('roster-select'), findsOneWidget);
      });
    }

    for (final (name, spec) in const [
      ('High contrast', SonusAppearanceSpec(highContrast: true)),
      ('Low effects', SonusAppearanceSpec(lowEffects: true)),
      (
        'Decoration Off',
        SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
    ]) {
      testWidgets('$name: flat panels, no glow', (tester) async {
        await pump(tester, spec: spec);
        await openRoster(tester);

        expect(tester.takeException(), isNull);
        expect(byKey('sonus-perspective-panel-transform'), findsNothing);
      });
    }

    testWidgets('portraits say who they are and whether they are previewed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await openRoster(tester);

      expect(
        find.bySemanticsLabel('Ada Lune, ranked number 1'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Ben Vale, unranked'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Ranked number 1 among your artists'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an artist without artwork shows initials', (tester) async {
      await pump(tester);
      await openRoster(tester);

      expect(find.text('AL'), findsWidgets);
    });

    testWidgets('with reduced motion the page buttons move at once', (
      tester,
    ) async {
      await pump(
        tester,
        artists: roster(40),
        ranks: const {},
        spec: const SonusAppearanceSpec(reduceMotion: true),
      );
      await openRoster(tester);

      await tester.tap(byKey('roster-page-next'));
      await tester.pump();

      final pages = tester.widget<PageView>(byKey('roster-pages'));
      expect(pages.controller!.page, 1);
    });
  });

  test('sort labels', () {
    expect(ArtistStatisticsSort.values.map(ArtistRosterPage.sortLabel), [
      'Name',
      'Most Played',
      'Listening Time',
      'Recently Added',
    ]);
  });
}
