import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/models/library_navigation_memory.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';

import '../../pages/library_page_test.dart' as base;

/// App Update 1.1: the Artist Roster's starting position and its short
/// navigation memory. The featured artist always belongs to the visible
/// page; the default is Page 1 with the sorted roster's first artist; the
/// page and artist are remembered for 15 minutes after leaving.
Finder byKey(String key) => find.byKey(ValueKey<String>(key));

class _Stats implements ArtistLibraryStatisticsService {
  _Stats(this.artists, {this.delay = Duration.zero});

  final List<LibraryArtist> artists;

  /// As on the device, the statistics can arrive after the first frame
  /// (the Roster then updates).
  final Duration delay;

  /// Artist a<i> has 100 - i streams: "Most played" runs a0, a1, …
  /// whatever order the library lists them in.
  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return ArtistLibraryStatisticsSnapshot([
      for (final artist in artists)
        ArtistLibraryStatistics(
          artist: artist,
          rank: _number(artist) + 1,
          qualifiedStreams: 100 - _number(artist),
          listened: Duration(minutes: 100 - _number(artist)),
        ),
    ]);
  }

  static int _number(LibraryArtist artist) =>
      int.parse(artist.artistId.substring(1));
}

/// 30 artists (three pages of ten), named so that A-Z order differs from
/// the streams order: artist i is named from the end of the alphabet.
List<LibraryArtist> _roster() => [
  for (var i = 0; i < 30; i++)
    base.createArtist(
      artistId: 'a$i',
      name: '${String.fromCharCode(90 - i % 26)}${i ~/ 26} Artist $i',
      albumCount: 1,
      songCount: 2,
    ),
];

class _Clock {
  DateTime now = DateTime(2026, 11, 6, 20);
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late _Clock clock;
  late LibraryNavigationMemory memory;

  setUp(() {
    clock = _Clock();
    memory = LibraryNavigationMemory(clock: () => clock.now);
  });

  Future<void> enter(
    WidgetTester tester, {
    List<LibraryArtist>? artists,
    LibraryNavigationMemory? using,
    Duration statsDelay = Duration.zero,
  }) async {
    final list = artists ?? _roster();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryQueryRepository?>.value(
            value: base.FakeLibraryQueryRepository(artists: list),
          ),
          Provider<ArtistLibraryStatisticsService?>.value(
            value: _Stats(list, delay: statsDelay),
          ),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(body: LibraryPage(navigationMemory: using ?? memory)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (statsDelay > Duration.zero) {
      // Let the late statistics arrive, as on the device.
      await tester.pump(statsDelay);
      await tester.pumpAndSettle();
    }
  }

  /// Leaves the Library (its page leaves the tree, as on a tab switch).
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  String page(WidgetTester tester) =>
      tester.widget<Text>(byKey('roster-page-indicator')).data!;
  String featured(WidgetTester tester) =>
      tester.widget<Text>(byKey('roster-featured-name')).data!;
  bool visible(String id) => byKey('roster-tile-$id').evaluate().isNotEmpty;

  /// The featured artist is a$index: named, previewed in the grid on the
  /// visible page, and the one SELECT ARTIST would open.
  void expectFeatured(WidgetTester tester, int index, String pageText) {
    expect(page(tester), pageText);
    expect(featured(tester), _name(index));
    expect(visible('a$index'), isTrue, reason: 'on the visible page');
    // Its thumbnail is highlighted: selected, hinted "Previewing".
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp('^${_name(index, upper: false)},')),
      ),
      isSemantics(isSelected: true, hint: 'Previewing'),
    );
  }

  Future<void> tapTile(WidgetTester tester, int index) async {
    tester
        .widget<InkWell>(
          find.descendant(
            of: byKey('roster-tile-a$index'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
  }

  testWidgets('fresh entry: Page 1, the first artist featured and '
      'highlighted', (tester) async {
    await enter(tester);
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('Next, Previous and swiping feature the first artist of the '
      'page shown', (tester) async {
    await enter(tester);

    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    expectFeatured(tester, 10, 'Page 2 of 3');

    await tester.drag(byKey('roster-pages'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expectFeatured(tester, 20, 'Page 3 of 3');

    await tester.tap(byKey('roster-page-previous'));
    await tester.pumpAndSettle();
    expectFeatured(tester, 10, 'Page 2 of 3');
  });

  testWidgets('tapping a thumbnail features that artist', (tester) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 14);
    expectFeatured(tester, 14, 'Page 2 of 3');
  });

  // App Update 1.2 (BUG-01): entering the Library destination again starts
  // on Page 1 with the first artist, however soon (App Update 1.1 restored
  // the place for 15 minutes).
  testWidgets('returning to the Library starts again on Page 1 with the '
      'first artist, however soon', (tester) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 16);
    await leave(tester);

    clock.advance(const Duration(seconds: 5));
    await enter(tester);
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('returning from a page opened over the Library, such as an '
      'Artist Profile, keeps the page and artist', (tester) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 16);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Artist Profile')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    clock.advance(const Duration(minutes: 30));
    navigator.pop();
    await tester.pumpAndSettle();

    expectFeatured(tester, 16, 'Page 2 of 3');
  });

  testWidgets('a page turn is quick and lands exactly on the page', (
    tester,
  ) async {
    await enter(tester);
    final pages = tester.widget<PageView>(byKey('roster-pages')).controller!;

    await tester.tap(byKey('roster-page-next'));
    await tester.pump();
    var overshoot = false;
    for (var ms = 0; ms < 150; ms += 10) {
      await tester.pump(const Duration(milliseconds: 10));
      if ((pages.page ?? 0) > 1.0001) overshoot = true;
    }
    await tester.pump(const Duration(milliseconds: 20));

    expect(overshoot, isFalse);
    expect(pages.page, 1.0, reason: 'settled within 150 ms');
    await tester.pumpAndSettle();
    expectFeatured(tester, 10, 'Page 2 of 3');
  });

  testWidgets('returning after 15 minutes starts again on Page 1', (
    tester,
  ) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 16);
    await leave(tester);

    clock.advance(const Duration(minutes: 15, seconds: 1));
    await enter(tester);
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('a fresh app launch starts on Page 1', (tester) async {
    await enter(tester);
    await tapTile(tester, 7);
    await leave(tester);

    // A new process has a new, empty memory.
    await enter(tester, using: LibraryNavigationMemory(clock: () => clock.now));
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('the app in the background counts as leaving', (tester) async {
    await enter(tester);
    await tapTile(tester, 5);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    clock.advance(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expectFeatured(tester, 5, 'Page 1 of 3');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    clock.advance(const Duration(minutes: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('browsing for a long time never resets', (tester) async {
    await enter(tester);
    await tapTile(tester, 3);
    clock.advance(const Duration(hours: 2));
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    expectFeatured(tester, 10, 'Page 2 of 3');
  });

  testWidgets('A-Z features the letter\'s first artist on its page', (
    tester,
  ) async {
    await enter(tester);
    await tester.tap(byKey('roster-az'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-letter-M'));
    await tester.pumpAndSettle();

    // By name, "M0 Artist 13" is the 14th: page 2.
    expect(find.text('Sort: Name'), findsOneWidget);
    expect(page(tester), 'Page 2 of 3');
    expect(featured(tester), 'M0 ARTIST 13');
    expect(visible('a13'), isTrue);
  });

  testWidgets('sorting keeps a still-listed artist, shown on its page', (
    tester,
  ) async {
    await enter(tester);
    await tapTile(tester, 2);
    await tester.tap(byKey('roster-sort'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-sort-name').last);
    await tester.pumpAndSettle();

    // By name, "X0 Artist 2" is the 28th: page 3.
    expect(featured(tester), 'X0 ARTIST 2');
    expect(page(tester), 'Page 3 of 3');
    expect(visible('a2'), isTrue);
  });

  testWidgets('filtering out the featured artist features the first one', (
    tester,
  ) async {
    final all = _roster();
    await enter(tester, artists: all);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 12);
    await leave(tester);

    // The artist is gone (removed or hidden) when the Roster comes back.
    await enter(
      tester,
      artists: [
        for (final a in all)
          if (a.artistId != 'a12') a,
      ],
    );
    expectFeatured(tester, 0, 'Page 1 of 3');
  });

  testWidgets('no artists: the empty state', (tester) async {
    await enter(tester, artists: const []);
    expect(find.text('No artists yet'), findsOneWidget);
    expect(byKey('roster-featured-name'), findsNothing);
  });

  // App Update 1.1: the Film Reel is retired, so the Library opens straight
  // into the Roster. As on the device, the library lists artists in another
  // order than "Most played" and the statistics arrive after the first
  // frame; the Roster still starts on Page 1 with its first artist.
  group('the Roster as the only artist view', () {
    const late = Duration(milliseconds: 300);
    List<LibraryArtist> listed() => _roster().reversed.toList();

    testWidgets('1. opens directly in the Roster: no view switch', (
      tester,
    ) async {
      await enter(tester, artists: listed(), statsDelay: late);

      expect(byKey('artist-roster'), findsOneWidget);
      expect(byKey('film-reel-pages'), findsNothing);
      expect(byKey('library-view-reel'), findsNothing);
      expect(byKey('library-view-roster'), findsNothing);
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('2. a fresh launch: Page 1, first artist', (tester) async {
      await enter(
        tester,
        artists: listed(),
        statsDelay: late,
        using: LibraryNavigationMemory(clock: () => clock.now),
      );
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('3. returning to the Library: Page 1, first artist '
        '(App Update 1.2, BUG-01)', (tester) async {
      await enter(tester, artists: listed(), statsDelay: late);
      await tester.tap(byKey('roster-page-next'));
      await tester.pumpAndSettle();
      await tapTile(tester, 14);
      await leave(tester);

      clock.advance(const Duration(minutes: 10));
      await enter(tester, artists: listed(), statsDelay: late);
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('4. after 15 minutes: Page 1, first artist', (tester) async {
      await enter(tester, artists: listed());
      await tapTile(tester, 6);
      await leave(tester);

      clock.advance(const Duration(minutes: 16));
      await enter(tester, artists: listed(), statsDelay: late);
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('5. tapping an artist and SELECT ARTIST', (tester) async {
      await enter(tester, artists: listed(), statsDelay: late);
      await tapTile(tester, 4);
      expectFeatured(tester, 4, 'Page 1 of 3');

      await tester.tap(byKey('roster-select'));
      await tester.pumpAndSettle();
      expect(byKey('artist-profile-page'), findsOneWidget);
      expect(find.text(_name(4, upper: false)), findsWidgets);
    });

    testWidgets('6. paging and sorting', (tester) async {
      await enter(tester, artists: listed(), statsDelay: late);

      await tester.tap(byKey('roster-page-next'));
      await tester.pumpAndSettle();
      expectFeatured(tester, 10, 'Page 2 of 3');

      await tester.tap(byKey('roster-sort'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('roster-sort-name').last);
      await tester.pumpAndSettle();
      // Sorting keeps the still-listed featured artist, on its new page.
      expect(featured(tester), _name(10));
      expect(visible('a10'), isTrue);
    });
  });

  testWidgets('SELECT ARTIST opens the featured artist of the visible page', (
    tester,
  ) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-select'));
    await tester.pumpAndSettle();

    expect(byKey('artist-profile-page'), findsOneWidget);
    expect(find.text(_name(10, upper: false)), findsWidgets);
  });
}

String _name(int i, {bool upper = true}) {
  final name = '${String.fromCharCode(90 - i % 26)}${i ~/ 26} Artist $i';
  return upper ? name.toUpperCase() : name;
}
