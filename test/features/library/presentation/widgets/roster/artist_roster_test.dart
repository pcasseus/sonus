// UI redesign L2 and the Roster-first Library: the Artist Roster is the
// Library's default screen, through the real LibraryPage.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/presentation/widgets/playback_host.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_framed_artwork.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/widgets/roster/artist_roster.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';

import '../../../../../support/device_layout.dart';
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

      // In the Roster, one button: to the Film Reel.
      expect(find.bySemanticsLabel('Film Reel view'), findsOneWidget);
      expect(byKey('library-view-roster'), findsNothing);
      expect(
        find.bySemanticsLabel('Artist Roster, select an artist'),
        findsOneWidget,
        reason: 'the screen is named',
      );

      // In the Film Reel, both, the Film Reel's lit.
      await switchTo(tester, 'reel');
      final reel = tester.getSemantics(byKey('library-view-reel'));
      expect(reel.flagsCollection.isSelected, Tristate.isTrue);
      expect(find.bySemanticsLabel('Artist Roster view'), findsOneWidget);
      handle.dispose();
    });
  });

  group('finding artists', () {
    testWidgets('no search field: a search icon opens the Artist Finder, '
        'and the chosen artist is previewed on its page', (tester) async {
      await pump(tester, artists: roster(40), ranks: const {});
      await openRoster(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Page 1 of 4'), findsOneWidget);

      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      expect(byKey('artist-finder-page'), findsOneWidget);
      await tester.enterText(byKey('artist-finder-field'), 'artist n1');
      await tester.pumpAndSettle();
      await tester.tap(byKey('artist-finder-artist-39'));
      await tester.pumpAndSettle();

      expect(byKey('artist-finder-page'), findsNothing);
      expect(featuredName(tester), 'ARTIST N1');
      expect(find.text('Page 3 of 4'), findsOneWidget, reason: 'N1 is 28th');
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
      // ten to a page:
      // on page 3 of 4.
      expect(find.text('Sort: Name'), findsOneWidget);
      expect(find.text('Page 4 of 6'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('roster-tile-artist-36')),
        findsOneWidget,
      );
    });
  });

  Finder tiles() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('roster-tile-'),
  );

  /// The Library tab as on the phone: the Sonus bar and tabs, the real
  /// playback host with a song queued (so the mini-player shows), Roboto,
  /// and the device's measured size and insets.
  Future<void> pumpInShell(
    WidgetTester tester, {
    List<LibraryArtist>? artists,
    Size size = s26UltraSize,
    double ratio = s26UltraRatio,
    double textScale = 1,
    Map<String, int>? ranks,
  }) async {
    setDevice(tester, size: size, ratio: ratio);
    final list = artists ?? roster(60);
    final engine = QueuedSongEngine();
    final coordinator = PlaybackCoordinator(engine: engine);
    final playback = PlaybackStateController(coordinator: coordinator);
    addTearDown(engine.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final routes = PlaybackHostRouteObserver();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaybackCoordinator>.value(value: coordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(
            value: playback,
          ),
          Provider<LibraryQueryRepository?>.value(
            value: base.FakeLibraryQueryRepository(artists: list),
          ),
          Provider<ArtistLibraryStatisticsService?>.value(
            value: _Stats(
              list,
              ranks ?? {for (final (i, a) in list.indexed) a.artistId: i + 1},
            ),
          ),
        ],
        child: MaterialApp(
          theme: withRealRoboto(
            SonusThemeFactory.build(const SonusAppearanceSpec()),
          ),
          navigatorKey: navigatorKey,
          navigatorObservers: [routes],
          builder: (context, navigator) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: PlaybackHost(
              navigatorKey: navigatorKey,
              routes: routes,
              child: navigator!,
            ),
          ),
          home: AppShellPage(
            pageBuilder: (destination) => destination == AppDestination.library
                ? const LibraryPage()
                : Center(child: Text('${destination.label} page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The tabs scroll sideways: bring Library into view, then tap it.
    await tester.ensureVisible(byKey('app-tab-library'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('app-tab-library'));
    await tester.pumpAndSettle();
  }

  double miniPlayerTop(WidgetTester tester) =>
      tester.getTopLeft(byKey('playback-host-bar')).dy;

  int tilesInView(WidgetTester tester) {
    final selectTop = tester.getTopLeft(byKey('roster-select')).dy;
    final rosterTop = tester.getTopLeft(byKey('artist-roster')).dy;
    return tiles().evaluate().where((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return rect.top >= rosterTop && rect.bottom <= selectTop;
    }).length;
  }

  /// The statistics panel beside the portrait: its own height, and the
  /// height it is shown at.
  (double, double) statisticsShown(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(
      find
          .ancestor(
            of: byKey('roster-top-track'),
            matching: find.byType(OverflowBox),
          )
          .first,
    );
    final panel = (box as RenderObjectWithChildMixin<RenderBox>).child!;
    return (panel.size.height, box.size.height);
  }

  void expectFullSizeStatistics(WidgetTester tester) {
    expect(
      find.ancestor(
        of: byKey('roster-top-track'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
      reason: 'statistics are never scaled',
    );
    if (byKey('roster-compact').evaluate().isEmpty) {
      final (own, shown) = statisticsShown(tester);
      expect(
        own,
        lessThanOrEqualTo(shown + 0.5),
        reason: 'statistics are not clipped',
      );
    }
  }

  // Device QA (S26 Ultra), Option C: the Roster stays in the Library tab,
  // below the Sonus bar and tabs and above the mini-player, with one row of
  // controls, the featured artist and two rows of portraits.
  group('in the Library tab (Galaxy S26 Ultra, Option C)', () {
    setUpAll(loadRealRoboto);

    testWidgets('384 x 832: the Sonus bar and mini-player stay; controls, '
        'featured artist, 5 x 2 portraits and SELECT ARTIST all fit', (
      tester,
    ) async {
      await pumpInShell(tester);

      expect(byKey('app-tab-library'), findsOneWidget, reason: 'tabs stay');
      expect(byKey('playback-host-bar'), findsOneWidget);
      expect(byKey('roster-compact'), findsNothing, reason: 'no scrolling');
      final roster = tester.getRect(byKey('artist-roster'));
      expect(roster.top, 144, reason: 'below the 40dp status bar and bar');
      expect(roster.bottom, miniPlayerTop(tester));

      expect(tilesInView(tester), 10, reason: 'five portraits, two rows');
      expect(byKey('roster-tile-artist-10'), findsNothing, reason: 'page 2');
      expect(tester.getSize(byKey('roster-tile-artist-0')).width, 56);

      // One row of controls at the top.
      final find0 = tester.getRect(byKey('roster-find'));
      final sort = tester.getRect(byKey('roster-sort'));
      final letters = tester.getRect(byKey('roster-az'));
      final reel = tester.getRect(byKey('library-view-reel'));
      for (final rect in [sort, letters, reel]) {
        expect(rect.center.dy, closeTo(find0.center.dy, 1));
      }
      expect(find.text('Sort: Most Played'), findsOneWidget);

      expect(byKey('roster-select-label'), findsOneWidget);
      // V3: the name runs across the full width, above the artwork.
      final name = tester.getRect(byKey('roster-featured-name'));
      final frame = tester.getRect(byKey('roster-featured-frame'));
      expect(name.bottom, lessThan(frame.top));
      expect(
        tester.getRect(byKey('roster-rank')).bottom,
        lessThan(frame.top),
        reason: 'the rank stays with the name',
      );
      // Wider, near-square artwork (about 52% of the row) for group photos.
      expect(frame.width, greaterThan(175));
      expect(frame.width / frame.height, inInclusiveRange(0.85, 1.15));
      final stats = tester.getRect(byKey('roster-stat-releases'));
      expect(stats.left, greaterThan(frame.right), reason: 'stats beside');
      expectFullSizeStatistics(tester);
      expect(
        tester.getRect(byKey('roster-top-track')).bottom,
        lessThan(tester.getTopLeft(byKey('roster-pages')).dy),
        reason: 'the top track shows above the grid',
      );

      final select = tester.getRect(byKey('roster-select'));
      expect(select.height, greaterThanOrEqualTo(56));
      expect(select.bottom, lessThanOrEqualTo(miniPlayerTop(tester)));
      expect(find.text('Page 1 of 6'), findsOneWidget);
      expect(find.text('60 artists'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the name keeps its dramatic size beside full statistics', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        artists: [
          base.createArtist(
            artistId: 'mb',
            name: 'Madison Beer',
            albumCount: 12,
            songCount: 148,
          ),
          ...roster(20),
        ],
      );

      final name = tester.renderObject<RenderBox>(
        byKey('roster-featured-name'),
      );
      final shown = tester.getSize(
        find
            .ancestor(
              of: byKey('roster-featured-name'),
              matching: find.byType(FittedBox),
            )
            .first,
      );
      expect(shown.height / name.size.height, greaterThan(0.9));
      expectFullSizeStatistics(tester);
    });

    testWidgets('text at 1.15x: the scrolling layout (V3: the full-width '
        'header and tiles need the height), grid first, full size', (
      tester,
    ) async {
      await pumpInShell(tester, textScale: 1.15);

      expect(byKey('roster-compact'), findsOneWidget);
      expect(tilesInView(tester), 10);
      expectFullSizeStatistics(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360 x 780: the full-width name leaves too little height, '
        'so the scrolling layout keeps everything at full size', (
      tester,
    ) async {
      await pumpInShell(tester, size: const Size(360, 780), ratio: 3);

      expect(byKey('roster-compact'), findsOneWidget);
      expect(tilesInView(tester), 10, reason: 'the grid leads');
      expectFullSizeStatistics(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412 x 915: still two rows, the featured artist gets more', (
      tester,
    ) async {
      await pumpInShell(tester, size: const Size(412, 915), ratio: 2.625);

      expect(tilesInView(tester), 10);
      expect(
        tester.getSize(byKey('roster-featured-frame')).height,
        greaterThan(240),
      );
      expectFullSizeStatistics(tester);
    });

    testWidgets('a tablet shows more rows', (tester) async {
      await pumpInShell(tester, size: const Size(800, 1280), ratio: 2);

      expect(tilesInView(tester), greaterThanOrEqualTo(21));
      expectFullSizeStatistics(tester);
    });

    for (final (label, size, ratio, scale) in [
      ('S26 Ultra at 1.3x text', s26UltraSize, s26UltraRatio, 1.3),
      ('S26 Ultra at 2x text', s26UltraSize, s26UltraRatio, 2.0),
      ('360 x 780 at 1.15x text', const Size(360, 780), 3.0, 1.15),
      ('320 x 690', const Size(320, 690), 2.0, 1.0),
      ('320 x 690 at 2x text', const Size(320, 690), 2.0, 2.0),
    ]) {
      testWidgets('$label: a scrolling layout at full text size, portraits '
          'before statistics, SELECT ARTIST in place', (tester) async {
        await pumpInShell(tester, size: size, ratio: ratio, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(byKey('roster-compact'), findsOneWidget);
        expect(byKey('app-tab-library'), findsOneWidget);
        expectFullSizeStatistics(tester);
        final select = tester.getRect(byKey('roster-select'));
        expect(select.bottom, lessThanOrEqualTo(miniPlayerTop(tester)));
        expect(
          tester.getTopLeft(byKey('roster-pages')).dy,
          lessThan(tester.getTopLeft(byKey('roster-top-track')).dy),
          reason: 'the grid comes before the statistics',
        );

        // Every portrait can be reached by dragging the Roster up, from
        // near its top (outside the grid, so the grid's pages stay put).
        final selectTop = select.top;
        final rosterTop = tester.getRect(byKey('artist-roster')).topCenter;
        for (var i = 0; i < 12; i++) {
          final tile = tester.getRect(byKey('roster-tile-artist-3'));
          if (tile.bottom <= selectTop) break;
          await tester.dragFrom(
            rosterTop.translate(0, 30),
            const Offset(0, -80),
          );
          await tester.pumpAndSettle();
        }
        expect(
          tester.getRect(byKey('roster-tile-artist-3')).bottom,
          lessThanOrEqualTo(selectTop),
        );
        await tester.tap(byKey('roster-tile-artist-3'));
        await tester.pumpAndSettle();
        expect(featuredName(tester), 'ARTIST D0');
        await tester.ensureVisible(byKey('roster-find'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(byKey('roster-find')).height,
          greaterThanOrEqualTo(48),
        );
      });
    }

    // UI redesign V3: the featured layout of the approved Roster reference.
    testWidgets('V3: statistics as a two-by-two grid, the top track below', (
      tester,
    ) async {
      await pumpInShell(tester);

      Rect at(String id) => tester.getRect(byKey('roster-stat-$id'));
      expect(at('releases').left, lessThan(at('songs').left));
      expect(at('releases').top, closeTo(at('songs').top, 1));
      expect(at('streams').top, greaterThan(at('releases').bottom));
      expect(at('listened').left, closeTo(at('songs').left, 1));
      expect(
        tester.getRect(byKey('roster-top-track')).top,
        greaterThan(at('streams').bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('V3: a very long name stays on one line, scaled, not cut', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        artists: [
          base.createArtist(
            artistId: 'long',
            name: 'The Extraordinarily Long Original Broadway Cast',
          ),
          ...roster(12),
        ],
      );

      final name = tester.renderObject<RenderBox>(
        byKey('roster-featured-name'),
      );
      final shown = tester.getSize(
        find
            .ancestor(
              of: byKey('roster-featured-name'),
              matching: find.byType(FittedBox),
            )
            .first,
      );
      expect(shown.width, lessThanOrEqualTo(s26UltraSize.width));
      expect(shown.height, lessThan(name.size.height + 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('V3: the artwork frame carries an accent rim', (tester) async {
      await pumpInShell(tester);

      final frame =
          tester.widget<DecoratedBox>(byKey('roster-featured-frame')).decoration
              as BoxDecoration;
      expect((frame.border! as Border).top.width, 1.5);
      expect(byKey('roster-featured-portrait'), findsOneWidget);
    });

    testWidgets('the Finder and SELECT ARTIST open from the tab, and Back '
        'returns to the Roster with the Sonus bar', (tester) async {
      await pumpInShell(tester);

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
      expect(byKey('app-tab-library'), findsOneWidget);
    });

    testWidgets('the Film Reel switch and the other tabs work as usual', (
      tester,
    ) async {
      await pumpInShell(tester);

      await tester.tap(byKey('library-view-reel'));
      await tester.pumpAndSettle();
      expect(byKey('film-reel-pages'), findsOneWidget);
      await tester.tap(byKey('library-view-roster'));
      await tester.pumpAndSettle();
      expect(byKey('artist-roster'), findsOneWidget);

      await tester.ensureVisible(byKey('app-tab-playlists'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('app-tab-playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Playlists page'), findsOneWidget);
    });
  });

  group('the Artist Finder with the keyboard open (S26 Ultra)', () {
    setUpAll(loadRealRoboto);
    const keyboard = 330.0;

    Future<void> openFinder(
      WidgetTester tester, {
      Size size = s26UltraSize,
      double ratio = s26UltraRatio,
      double textScale = 1,
    }) async {
      await pumpInShell(
        tester,
        size: size,
        ratio: ratio,
        textScale: textScale,
        ranks: const {},
      );
      await tester.ensureVisible(byKey('roster-find'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('roster-find'));
      await tester.pumpAndSettle();
      // The field takes focus at once; the keyboard opens.
      expect(
        tester.widget<TextField>(byKey('artist-finder-field')).autofocus,
        isTrue,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * ratio);
      await tester.pumpAndSettle();
    }

    double keyboardTop(WidgetTester tester) =>
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        keyboard;

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
      expect(rowsAboveKeyboard(tester), greaterThanOrEqualTo(4));
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
        'Roster on its page', (tester) async {
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
      await openFinder(
        tester,
        size: const Size(320, 690),
        ratio: 2,
        textScale: 2,
      );
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

      expect(find.text('Page 1 of 200'), findsOneWidget);
      expect(builtTiles(), lessThanOrEqualTo(10));

      for (var i = 0; i < 3; i++) {
        await tester.tap(byKey('roster-page-next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Page 4 of 200'), findsOneWidget);
      expect(builtTiles(), lessThanOrEqualTo(20));

      await tester.tap(byKey('roster-page-previous'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 200'), findsOneWidget);
      expect(stats.loads, 1, reason: 'no statistics read while browsing');
      expect(tester.takeException(), isNull);
    });
  });

  group('layout and accessibility', () {
    testWidgets('typical phone: five portraits a row, two rows', (
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
      expect(rects, hasLength(10));
      expect({for (final r in rects) r.left.round()}, hasLength(5));
      expect({for (final r in rects) r.top.round()}, hasLength(2));
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

    // Device QA: the featured artist had a faded, larger copy of the
    // portrait behind it, and group photos lost people at both edges.
    testWidgets('the featured portrait has no ghost copy behind it', (
      tester,
    ) async {
      await pump(tester);

      final featured = byKey('roster-featured-ada');
      expect(
        find.descendant(of: featured, matching: find.byType(Opacity)),
        findsNothing,
        reason: 'no faded duplicate',
      );
      expect(
        find.descendant(of: featured, matching: find.text('AL')),
        findsOneWidget,
        reason: 'one portrait (initials, as Ada has no artwork)',
      );
    });

    testWidgets('featured artwork is framed whole rather than cropped to the '
        'frame; the small tiles keep their angled crop', (tester) async {
      final pictured = LibraryArtist(
        artistId: 'cast',
        name: 'Victorious Cast',
        albumCount: 3,
        songCount: 40,
        dateAdded: DateTime(2026),
        topArtistsArtworkPath: '/artwork/victorious-cast.jpg',
      );
      await pump(tester, artists: [pictured, ...three], ranks: const {});

      final featured = byKey('roster-featured-cast');
      expect(
        find.descendant(
          of: featured,
          matching: find.byType(SonusFramedArtwork),
        ),
        findsOneWidget,
      );
      final tile = byKey('roster-tile-cast');
      expect(
        find.descendant(of: tile, matching: find.byType(SonusFramedArtwork)),
        findsNothing,
      );
      final tileImage = tester.widget<Image>(
        find.descendant(of: tile, matching: find.byType(Image)),
      );
      expect(tileImage.fit, BoxFit.cover);
    });

    testWidgets('narrow screen and large text: one framed portrait, no '
        'ghost, nothing overflows', (tester) async {
      final pictured = LibraryArtist(
        artistId: 'flo',
        name: 'FLO',
        albumCount: 2,
        songCount: 20,
        dateAdded: DateTime(2026),
        headerArtworkPath: '/artwork/flo-banner.jpg',
      );
      await pump(
        tester,
        artists: [pictured, ...three],
        ranks: const {},
        size: const Size(320, 640),
        textScale: 2,
      );

      expect(byKey('roster-compact'), findsOneWidget);
      final featured = byKey('roster-featured-flo');
      expect(
        find.descendant(
          of: featured,
          matching: find.byType(SonusFramedArtwork),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: featured, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
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
