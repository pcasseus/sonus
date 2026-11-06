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
import 'package:sonus_next/features/library/presentation/widgets/library_view_switch.dart';

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
  /// (the views then update, and the Film Reel reports its centred artist).
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
    LibraryView view = LibraryView.roster,
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
          home: Scaffold(
            body: LibraryPage(
              navigationMemory: using ?? memory,
              initialView: view,
            ),
          ),
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

  testWidgets('returning within 15 minutes restores the page and artist', (
    tester,
  ) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 16);
    await leave(tester);

    clock.advance(const Duration(minutes: 14, seconds: 59));
    await enter(tester);
    expectFeatured(tester, 16, 'Page 2 of 3');
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

  testWidgets('Roster and Film Reel share the featured artist', (tester) async {
    await enter(tester);
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tapTile(tester, 13);

    await tester.tap(byKey('library-view-reel'));
    await tester.pumpAndSettle();
    expect(byKey('film-reel-pages'), findsOneWidget);
    expect(find.textContaining('Artist 13'), findsWidgets);

    await tester.tap(byKey('library-view-roster'));
    await tester.pumpAndSettle();
    expectFeatured(tester, 13, 'Page 2 of 3');
  });

  // App Update 1.1 entry-state correction: the Roster's session is its
  // own; the Film Reel's automatic first centring never moves it.
  group('Roster session independent of the Film Reel', () {
    /// The library lists artists in the reverse of the "Most played"
    /// order (as the device lists them by name): the reel centres a29
    /// first, while the Roster's first (most played) is a0.
    const reelFirst = 29;
    List<LibraryArtist> listed() => _roster().reversed.toList();

    late WidgetTester current;

    /// The artist number of the reel's centred card (its neighbours are
    /// built too).
    int centred() {
      final pages = current.getRect(byKey('film-reel-pages'));
      int? best;
      var distance = double.infinity;
      for (var i = 0; i < 30; i++) {
        final card = byKey('artist-open-a$i');
        if (card.evaluate().isEmpty) continue;
        final d = (current.getCenter(card) - pages.center).distance;
        if (d < distance) {
          distance = d;
          best = i;
        }
      }
      return best!;
    }

    bool reelShows(int i) => centred() == i;

    Future<void> toRoster(WidgetTester tester) async {
      await tester.tap(byKey('library-view-roster').first);
      await tester.pumpAndSettle();
    }

    Future<void> toReel(WidgetTester tester) async {
      await tester.tap(byKey('library-view-reel').first);
      await tester.pumpAndSettle();
    }

    testWidgets('1. saved Film Reel view, fresh launch, then the Roster: '
        'Page 1, first artist', (tester) async {
      current = tester;
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      expect(reelShows(reelFirst), isTrue, reason: 'the reel is unchanged');

      await toRoster(tester);
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('2. saved Roster view, fresh launch: Page 1, first artist', (
      tester,
    ) async {
      current = tester;
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        using: LibraryNavigationMemory(clock: () => clock.now),
      );
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets("3. the reel's automatic selection stays the reel's", (
      tester,
    ) async {
      current = tester;
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      expect(reelShows(reelFirst), isTrue);
      await leave(tester);

      // Nothing was chosen: the Roster still starts at its default.
      clock.advance(const Duration(minutes: 2));
      await enter(tester, artists: listed());
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('4. switching views within 15 minutes keeps a choice made in '
        'either', (tester) async {
      current = tester;
      await enter(tester, artists: listed());
      await tester.tap(byKey('roster-page-next'));
      await tester.pumpAndSettle();
      await tapTile(tester, 14);

      await toReel(tester);
      expect(reelShows(14), isTrue, reason: "the Roster's choice");

      // A reel swipe is a choice: the Roster follows it.
      await tester.tap(byKey('film-reel-next'));
      await tester.pumpAndSettle();
      final next = centred();
      expect(next, isNot(14));
      await toRoster(tester);
      expect(featured(tester), _name(next));
      expect(visible('a$next'), isTrue);

      await leave(tester);
      clock.advance(const Duration(minutes: 10));
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      expect(reelShows(next), isTrue);
      await toRoster(tester);
      expect(featured(tester), _name(next));
    });

    testWidgets('5. after 15 minutes both views start afresh', (tester) async {
      current = tester;
      await enter(tester, artists: listed());
      await tapTile(tester, 6);
      await leave(tester);

      clock.advance(const Duration(minutes: 16));
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      expect(reelShows(reelFirst), isTrue);
      await toRoster(tester);
      expectFeatured(tester, 0, 'Page 1 of 3');
    });

    testWidgets('6. after the reel: tapping an artist and SELECT ARTIST', (
      tester,
    ) async {
      current = tester;
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      await toRoster(tester);
      await tapTile(tester, 4);
      expectFeatured(tester, 4, 'Page 1 of 3');

      await tester.tap(byKey('roster-select'));
      await tester.pumpAndSettle();
      expect(byKey('artist-profile-page'), findsOneWidget);
      expect(find.text(_name(4, upper: false)), findsWidgets);
    });

    testWidgets('7. after the reel: paging and sorting', (tester) async {
      current = tester;
      await enter(
        tester,
        artists: listed(),
        statsDelay: const Duration(milliseconds: 300),
        view: LibraryView.filmReel,
      );
      await toRoster(tester);

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
