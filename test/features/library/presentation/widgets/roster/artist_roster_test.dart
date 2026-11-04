// UI redesign L2 and the Roster-first Library: the Artist Roster is the
// Library's default screen, through the real LibraryPage.
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
import 'package:sonus_next/features/library/presentation/widgets/roster/artist_roster.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

import '../../pages/library_page_test.dart' as base;

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
    expect(byKey('artist-roster'), findsOneWidget, reason: 'the default');
  }

  Future<void> switchTo(WidgetTester tester, String view) async {
    await tester.tap(byKey('library-view-$view'));
    await tester.pumpAndSettle();
  }

  String featuredName(WidgetTester tester) =>
      tester.widget<Text>(byKey('roster-featured-name')).data!;

  group('Roster-first Library', () {
    testWidgets('the Library opens on the Roster, on the first artist', (
      tester,
    ) async {
      await pump(tester);

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('film-reel-pages'), findsNothing);
      expect(find.text('3 artists'), findsOneWidget);
      expect(featuredName(tester), 'ADA LUNE');
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

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('artist-profile-page'), findsNothing);
      expect(featuredName(tester), 'ZED NIGHT');
      expect(find.text('#2 ARTIST RANK'), findsOneWidget);
      final tile = tester.getSemantics(byKey('roster-tile-zed'));
      expect(tile.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('SELECT ARTIST opens the previewed artist\'s profile, and '
        'Back returns to the Roster with it', (tester) async {
      final stats = await pump(tester);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('roster-select'));
      await tester.pumpAndSettle();
      expect(byKey('artist-profile-page'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(byKey('artist-roster'), findsOneWidget);
      expect(featuredName(tester), 'ZED NIGHT');
      expect(stats.loads, 1, reason: 'no reload for a profile visit');
    });

    testWidgets('the featured portrait opens the profile too', (tester) async {
      await pump(tester);

      await tester.tap(byKey('roster-featured-open'));
      await tester.pumpAndSettle();

      expect(byKey('artist-profile-page'), findsOneWidget);
    });

    testWidgets('the selection is shared with the Film Reel, both ways', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      await switchTo(tester, 'reel');
      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget, reason: 'Zed is centred');

      await tester.tap(byKey('film-reel-previous'));
      await tester.pumpAndSettle();
      await switchTo(tester, 'roster');

      expect(featuredName(tester), 'BEN VALE');
    });

    testWidgets('the Film Reel still opens profiles', (tester) async {
      await pump(tester);
      await switchTo(tester, 'reel');

      await tester.tap(byKey('artist-open-ada'));
      await tester.pumpAndSettle();

      expect(byKey('artist-profile-page'), findsOneWidget);
    });

    testWidgets('the Film Reel\'s search icon opens the Artist Finder, and '
        'the chosen artist is centred in the Film Reel', (tester) async {
      await pump(tester);
      await switchTo(tester, 'reel');

      await tester.tap(byKey('library-search-button'));
      await tester.pumpAndSettle();
      expect(byKey('artist-finder-page'), findsOneWidget);

      await tester.tap(byKey('artist-finder-zed'));
      await tester.pumpAndSettle();

      expect(byKey('artist-finder-page'), findsNothing);
      expect(byKey('film-reel-pages'), findsOneWidget, reason: 'same view');
      expect(find.text('#2'), findsOneWidget, reason: 'Zed is centred');
    });

    testWidgets('the view switch says which view is shown', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      final roster = tester.getSemantics(byKey('library-view-roster'));
      expect(roster.flagsCollection.isSelected, Tristate.isTrue);
      expect(find.bySemanticsLabel('Film Reel view'), findsOneWidget);
      handle.dispose();
    });
  });

  group('finding artists', () {
    testWidgets('no search field: a search icon opens the Artist Finder, '
        'and the chosen artist is previewed on its page', (tester) async {
      await pump(tester, artists: roster(40), ranks: const {});
      await openRoster(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      expect(byKey('artist-finder-page'), findsOneWidget);
      await tester.enterText(byKey('artist-finder-field'), 'artist n1');
      await tester.pumpAndSettle();
      await tester.tap(byKey('artist-finder-artist-39'));
      await tester.pumpAndSettle();

      expect(byKey('artist-finder-page'), findsNothing);
      expect(featuredName(tester), 'ARTIST N1');
      expect(find.text('Page 2 of 3'), findsOneWidget, reason: 'N1 is 28th');
      expect(byKey('roster-tile-artist-39'), findsOneWidget);
      expect(byKey('roster-select'), findsOneWidget);
    });

    testWidgets('closing the Finder without a choice changes nothing', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(byKey('roster-tile-zed'));
      await tester.pumpAndSettle();

      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(featuredName(tester), 'ZED NIGHT');
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

      await switchTo(tester, 'reel');
      await switchTo(tester, 'roster');
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

  // The Galaxy S26 Ultra: 412 x 891dp, a 40dp status bar, a 24dp gesture
  // bar and a 72dp mini-player below every route (as the playback host
  // lays it out).
  const dpr = 3.5;
  const screen = Size(412, 891);
  const miniPlayer = 72.0;
  const keyboard = 350.0;

  void phone(WidgetTester tester, {Size size = screen}) {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = size * dpr;
    tester.view.padding = const FakeViewPadding(
      top: 40 * dpr,
      bottom: 24 * dpr,
    );
    addTearDown(tester.view.reset);
  }

  /// A stand-in for the playback host: routes above, a mini-player below.
  Widget withMiniPlayer(BuildContext context, Widget? navigator) => Column(
    children: [
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: navigator!,
        ),
      ),
      Container(
        key: const ValueKey<String>('fake-mini-player'),
        height: miniPlayer + MediaQuery.paddingOf(context).bottom,
        color: const Color(0xFF222222),
      ),
    ],
  );

  Finder tiles() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('roster-tile-'),
  );

  // Device QA (S26 Ultra): inside the Library tab the Roster sat below the
  // Sonus title bar and tabs and above the mini-player, fell back to its
  // compact layout, and its portrait grid was almost entirely hidden.
  group('full screen in the app shell (S26 Ultra)', () {
    // The tabs scroll sideways: bring one into view, then tap it.
    Future<void> tapTab(WidgetTester tester, String name) async {
      await tester.ensureVisible(byKey('app-tab-$name'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('app-tab-$name'));
      await tester.pumpAndSettle();
    }

    Future<void> pumpShell(
      WidgetTester tester, {
      List<LibraryArtist>? artists,
      Size size = screen,
      double textScale = 1,
    }) async {
      phone(tester, size: size);
      final list = artists ?? roster(60);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LibraryQueryRepository?>.value(
              value: base.FakeLibraryQueryRepository(artists: list),
            ),
            Provider<ArtistLibraryStatisticsService?>.value(
              value: _Stats(list, const {}),
            ),
          ],
          child: MaterialApp(
            theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
            builder: (context, navigator) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Builder(
                builder: (context) => withMiniPlayer(context, navigator),
              ),
            ),
            home: AppShellPage(
              pageBuilder: (destination) =>
                  destination == AppDestination.library
                  ? const LibraryPage()
                  : Center(child: Text('${destination.label} page')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapTab(tester, 'library');
    }

    double miniPlayerTop(WidgetTester tester) =>
        tester.getTopLeft(byKey('fake-mini-player')).dy;

    testWidgets('the Roster takes the screen: the Sonus bar folds away and '
        'three full rows of portraits show above the mini-player', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('app-tab-library'), findsNothing, reason: 'bar folded');
      expect(byKey('roster-compact'), findsNothing, reason: 'full layout');
      final roster = tester.getRect(byKey('artist-roster'));
      expect(roster.top, 0);
      expect(roster.bottom, miniPlayerTop(tester));

      final visible = tiles().evaluate().where((element) {
        final rect = tester.getRect(find.byWidget(element.widget));
        return rect.top >= 40 && rect.bottom <= miniPlayerTop(tester);
      }).length;
      expect(visible, 15, reason: 'five portraits, three rows');
      final tile = tester.getRect(byKey('roster-tile-artist-0'));
      expect(tile.width, greaterThan(60));

      final header = tester.getRect(find.text('Artist Roster'));
      expect(header.top, greaterThanOrEqualTo(40), reason: 'below status bar');
      final portrait = tester.getRect(byKey('roster-featured-portrait'));
      expect(portrait.height, greaterThan(180));
      final select = tester.getRect(byKey('roster-select'));
      expect(select.bottom, lessThanOrEqualTo(miniPlayerTop(tester)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Sonus navigation is one tap away, and leaves when '
        'dismissed', (tester) async {
      await pumpShell(tester);

      await tester.tap(byKey('roster-show-navigation'));
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsOneWidget);
      expect(byKey('app-tab-library'), findsOneWidget);
      expect(byKey('roster-compact'), findsNothing, reason: 'over the Roster');

      // Back hides it first.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsNothing);
      expect(byKey('artist-roster'), findsOneWidget);

      // So does a tap outside it.
      await tester.tap(byKey('roster-show-navigation'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 700));
      await tester.pumpAndSettle();
      expect(byKey('shell-revealed-bar'), findsNothing);
    });

    testWidgets('another tab from the revealed bar: its page, with the bar', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(byKey('roster-show-navigation'));
      await tester.pumpAndSettle();
      await tapTab(tester, 'playlists');

      expect(find.text('Playlists page'), findsOneWidget);
      expect(byKey('shell-revealed-bar'), findsNothing);
      expect(byKey('app-tab-library'), findsOneWidget, reason: 'normal bar');
    });

    testWidgets('the Film Reel keeps the Sonus bar; back on the Roster it '
        'folds away again', (tester) async {
      await pumpShell(tester);

      await tester.tap(byKey('library-view-reel'));
      await tester.pumpAndSettle();
      expect(byKey('film-reel-pages'), findsOneWidget);
      expect(byKey('app-tab-library'), findsOneWidget);

      await tester.tap(byKey('library-view-roster'));
      await tester.pumpAndSettle();
      expect(byKey('app-tab-library'), findsNothing);
    });

    testWidgets('the Finder and SELECT ARTIST open over the full Roster, and '
        'Back returns to it', (tester) async {
      await pumpShell(tester);

      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('artist-finder-field'), 'h0');
      await tester.pumpAndSettle();
      await tester.tap(byKey('artist-finder-artist-7'));
      await tester.pumpAndSettle();
      expect(featuredName(tester), 'ARTIST H0');

      await tester.tap(byKey('roster-select'));
      await tester.pumpAndSettle();
      expect(byKey('artist-profile-page'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(featuredName(tester), 'ARTIST H0');
      expect(byKey('app-tab-library'), findsNothing);
    });

    testWidgets('320dp with 2x text: no overflow, navigation reachable', (
      tester,
    ) async {
      await pumpShell(tester, size: const Size(320, 700), textScale: 2);

      expect(tester.takeException(), isNull);
      expect(byKey('roster-show-navigation'), findsOneWidget);
      expect(byKey('roster-find'), findsOneWidget);
    });
  });

  group('the Artist Finder with the keyboard open (S26 Ultra)', () {
    Future<void> openFinder(
      WidgetTester tester, {
      Size size = screen,
      double textScale = 1,
    }) async {
      phone(tester, size: size);
      final list = roster(60);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LibraryQueryRepository?>.value(
              value: base.FakeLibraryQueryRepository(artists: list),
            ),
            Provider<ArtistLibraryStatisticsService?>.value(
              value: _Stats(list, const {}),
            ),
          ],
          child: MaterialApp(
            theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
            builder: (context, navigator) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Builder(
                builder: (context) => withMiniPlayer(context, navigator),
              ),
            ),
            home: const Scaffold(body: LibraryPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // With large text the Roster scrolls: the icon may need bringing up.
      await tester.ensureVisible(byKey('roster-find'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      // The field takes focus at once; the keyboard opens.
      expect(
        tester.widget<TextField>(byKey('artist-finder-field')).autofocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * dpr);
      await tester.pumpAndSettle();
    }

    double keyboardTop(WidgetTester tester) =>
        tester.view.physicalSize.height / dpr - keyboard;

    Finder rows() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'artist-finder-artist-',
          ),
    );

    int rowsAboveKeyboard(WidgetTester tester) => rows().evaluate().where((e) {
      final rect = tester.getRect(find.byWidget(e.widget));
      return rect.top >= 0 && rect.bottom <= keyboardTop(tester);
    }).length;

    testWidgets('the field stays at the top and the matches fill the space '
        'above the keyboard', (tester) async {
      await openFinder(tester);

      final field = tester.getRect(byKey('artist-finder-field'));
      expect(field.bottom, lessThan(keyboardTop(tester)));
      expect(field.top, greaterThanOrEqualTo(40));
      expect(rowsAboveKeyboard(tester), greaterThanOrEqualTo(5));
      expect(byKey('fake-mini-player'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every match can be reached by scrolling', (tester) async {
      await openFinder(tester);
      await tester.enterText(byKey('artist-finder-field'), 'artist');
      await tester.pumpAndSettle();
      expect(find.text('60 matches'), findsOneWidget);

      // Unranked, so in name order: the last is "Artist Z1" (artist-51).
      await tester.scrollUntilVisible(
        byKey('artist-finder-artist-51'),
        200,
        scrollable: find
            .descendant(
              of: byKey('artist-finder-results'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final last = tester.getRect(byKey('artist-finder-artist-51'));
      expect(last.bottom, lessThanOrEqualTo(keyboardTop(tester) + 1));
    });

    testWidgets('one match, no match, and clearing', (tester) async {
      await openFinder(tester);

      await tester.enterText(byKey('artist-finder-field'), 'artist q1');
      await tester.pumpAndSettle();
      expect(find.text('1 match'), findsOneWidget);
      expect(rows(), findsOneWidget);

      await tester.enterText(byKey('artist-finder-field'), 'nobody');
      await tester.pumpAndSettle();
      expect(byKey('artist-finder-no-results'), findsOneWidget);
      expect(rows(), findsNothing);

      await tester.tap(byKey('artist-finder-clear'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(byKey('artist-finder-count')).data,
        '60 artists',
      );
      expect(
        tester.widget<TextField>(byKey('artist-finder-field')).controller!.text,
        isEmpty,
      );
    });

    testWidgets('choosing a match closes the Finder and previews it in the '
        'full Roster', (tester) async {
      await openFinder(tester);
      await tester.enterText(byKey('artist-finder-field'), 'artist q');
      await tester.pumpAndSettle();

      await tester.tap(byKey('artist-finder-artist-42'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      expect(byKey('artist-finder-page'), findsNothing);
      expect(featuredName(tester), 'ARTIST Q1');
      expect(byKey('roster-tile-artist-42'), findsOneWidget);
      expect(byKey('roster-select'), findsOneWidget);
    });

    testWidgets('320dp with 2x text and the keyboard open', (tester) async {
      await openFinder(tester, size: const Size(320, 700), textScale: 2);
      await tester.enterText(byKey('artist-finder-field'), 'artist');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final field = tester.getRect(byKey('artist-finder-field'));
      expect(field.bottom, lessThan(keyboardTop(tester)));
      expect(rowsAboveKeyboard(tester), greaterThanOrEqualTo(1));
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
    expect(ArtistStatisticsSort.values.map(ArtistRoster.sortLabel), [
      'Name',
      'Most Played',
      'Listening Time',
      'Recently Added',
    ]);
  });
}
