// The Library's Roster and Film Reel share one selection, kept by artist id,
// and every statistic shown belongs to the artist shown (device bug: the
// reel showed 3Quency's portrait and name with Madison Beer's statistics).
//
// Root cause: both views' PageViews saved their page in the Library tab's
// PageStorage (the shell keys each tab with a PageStorageKey). A new reel
// restored the page saved by the Roster grid or an earlier reel visit while
// its statistics followed the selected artist, so the portrait and the
// panels described different artists.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_count_label.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_backdrop.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_reel_statistics_controller.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/library/presentation/widgets/library_view_switch.dart';

import 'library_page_test.dart' as base;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

LibraryTrack _topSong(String artistId) => LibraryTrack(
  songId: 'top-$artistId',
  title: 'Top of $artistId',
  artistId: artistId,
  artistName: artistId,
  albumId: 'album-$artistId',
  albumTitle: 'Album',
  albumEditionId: 'edition-$artistId',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime(2026),
  isAvailable: true,
);

/// 24 artists, listed A-Z (as the library lists them); "3Quency" first.
/// Every value differs per artist so a mix-up is always visible.
final List<LibraryArtist> _artists = [
  for (final (index, name) in [
    '3Quency',
    'Ada Lune',
    'Ben Vale',
    'Cyd',
    'Dara Moss',
    'Eli Stone',
    'Fern',
    'Gus Tide',
    'Hana Reed',
    'Ivo',
    'Jun Park',
    'Kai Lark',
    'Lea Moon',
    'Madison Beer',
    'Nia Cole',
    'Oto',
    'Pia Rain',
    'Quinn',
    'Rae Holt',
    'Sol',
    'Tess Vale',
    'Uma',
    'Vik Ray',
    'Wren',
  ].indexed)
    LibraryArtist(
      artistId: 'id-$index',
      name: name,
      albumCount: 100 + index,
      songCount: 200 + index,
      dateAdded: DateTime(2026, 1, 1 + index),
      topArtistsArtworkPath: '/fixture/portrait-$index.jpg',
    ),
];

/// Ranks in an order unlike A-Z: Madison Beer is #1, 3Quency is last.
int _rankOf(LibraryArtist artist) {
  final index = int.parse(artist.artistId.substring(3));
  if (artist.name == 'Madison Beer') return 1;
  return 25 - index;
}

ArtistLibraryStatistics _statsOf(LibraryArtist artist, {int generation = 0}) {
  final rank = _rankOf(artist);
  return ArtistLibraryStatistics(
    artist: artist,
    rank: rank,
    qualifiedStreams: 1000 - rank + generation,
    listened: Duration(minutes: 500 - rank * 7 + generation),
    topTrack: ArtistTopTrack(
      track: _topSong(artist.artistId),
      streamCount: 50 - rank,
    ),
  );
}

ArtistLibraryStatisticsSnapshot _snapshot({int generation = 0}) =>
    ArtistLibraryStatisticsSnapshot([
      for (final artist in _artists) _statsOf(artist, generation: generation),
    ]);

/// Statistics whose loads complete only when the test says so, in any
/// order.
class _GatedStats implements ArtistLibraryStatisticsService {
  final List<Completer<ArtistLibraryStatisticsSnapshot>> loads = [];

  @override
  Future<ArtistLibraryStatisticsSnapshot> load() {
    final completer = Completer<ArtistLibraryStatisticsSnapshot>();
    loads.add(completer);
    return completer.future;
  }
}

class _ImmediateStats implements ArtistLibraryStatisticsService {
  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async => _snapshot();
}

Future<void> _pump(
  WidgetTester tester, {
  required ArtistLibraryStatisticsService stats,
  LibraryQueryRepository? repository,
  LibraryView initialView = LibraryView.roster,
  LibraryChangeSignal? signal,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<LibraryQueryRepository?>.value(
          value:
              repository ?? base.FakeLibraryQueryRepository(artists: _artists),
        ),
        Provider<ArtistLibraryStatisticsService?>.value(value: stats),
      ],
      child: MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        // As in the app shell: each tab keeps its state under a
        // PageStorageKey, which is what scrollables save their place in.
        home: Scaffold(
          body: KeyedSubtree(
            key: const PageStorageKey<String>('app-page-library'),
            child: LibraryPage(
              initialView: initialView,
              changes: signal ?? LibraryChangeSignal(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textIn(WidgetTester tester, Finder area) => tester
    .widgetList<Text>(find.descendant(of: area, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' | ');

/// The artist whose portrait is in the middle of the reel.
LibraryArtist _centredReelArtist(WidgetTester tester) {
  final pages = tester.getRect(byKey('film-reel-pages'));
  LibraryArtist? best;
  var bestDistance = double.infinity;
  for (final artist in _artists) {
    final card = byKey('artist-open-${artist.artistId}');
    if (card.evaluate().isEmpty) continue;
    final distance = (tester.getCenter(card) - pages.center).distance;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = artist;
    }
  }
  expect(best, isNotNull, reason: 'no portrait in the reel');
  return best!;
}

/// Every field the reel shows belongs to [artist]: the centred portrait and
/// name, the backdrop artwork, rank, releases, songs, streams, listening
/// time and top track.
void _expectReelShows(
  WidgetTester tester,
  LibraryArtist artist, {
  int generation = 0,
}) {
  final centred = _centredReelArtist(tester);
  expect(
    centred.artistId,
    artist.artistId,
    reason: 'centred portrait is ${centred.name}, expected ${artist.name}',
  );
  expect(byKey('film-reel-name-${artist.artistId}'), findsOneWidget);
  expect(
    tester.widget<Text>(byKey('film-reel-name-${artist.artistId}')).data,
    artist.name,
  );
  expect(
    tester
        .widget<SonusArtworkBackdrop>(find.byType(SonusArtworkBackdrop))
        .artworkPath,
    artist.topArtistsArtworkPath,
  );

  final stats = _statsOf(artist, generation: generation);
  expect(_textIn(tester, byKey('film-reel-rank')), contains('#${stats.rank}'));
  expect(
    _textIn(tester, byKey('film-reel-releases')),
    contains('${artist.albumCount}'),
  );
  expect(
    _textIn(tester, byKey('film-reel-songs')),
    contains('${artist.songCount}'),
  );
  expect(
    _textIn(tester, byKey('film-reel-streams')),
    contains('${stats.qualifiedStreams}'),
  );
  expect(
    _textIn(tester, byKey('film-reel-listened')),
    contains(sonusListeningTime(stats.listened!)),
  );
  expect(
    _textIn(tester, byKey('film-reel-top-track')),
    contains('Top of ${artist.artistId}'),
    reason: 'top track of ${centred.name}',
  );
}

/// Every field the Roster's featured artist shows belongs to [artist].
void _expectRosterShows(WidgetTester tester, LibraryArtist artist) {
  expect(byKey('roster-header-${artist.artistId}'), findsOneWidget);
  expect(
    tester.widget<Text>(byKey('roster-featured-name')).data,
    artist.name.toUpperCase(),
  );
  final stats = _statsOf(artist);
  expect(_textIn(tester, byKey('roster-rank')), contains('#${stats.rank} '));
  expect(
    _textIn(tester, byKey('roster-stat-releases')),
    contains('${artist.albumCount}'),
  );
  expect(
    _textIn(tester, byKey('roster-stat-songs')),
    contains('${artist.songCount}'),
  );
  expect(
    _textIn(tester, byKey('roster-stat-streams')),
    contains('${stats.qualifiedStreams}'),
  );
  expect(
    _textIn(tester, byKey('roster-stat-listened')),
    contains(sonusListeningTime(stats.listened!)),
  );
  expect(
    _textIn(tester, byKey('roster-top-track')),
    contains('Top of ${artist.artistId}'),
  );
  // The selected tile is on the page shown.
  expect(byKey('roster-tile-${artist.artistId}'), findsOneWidget);
}

LibraryArtist _named(String name) => _artists.firstWhere((a) => a.name == name);

Future<void> _switchTo(WidgetTester tester, LibraryView view) async {
  final page = tester.state<State<LibraryPage>>(find.byType(LibraryPage));
  // The view switch of either view.
  final key = view == LibraryView.filmReel
      ? 'library-view-reel'
      : 'library-view-roster';
  final button = byKey(key);
  expect(button, findsWidgets, reason: 'no $key on ${page.runtimeType}');
  await tester.tap(button.first);
  await tester.pumpAndSettle();
}

Future<void> _reelNext(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(byKey('film-reel-next'));
    await tester.pumpAndSettle();
  }
}

bool _enabled(WidgetTester tester, String key) =>
    tester
        .widget<IconButton>(
          find.descendant(of: byKey(key), matching: find.byType(IconButton)),
        )
        .onPressed !=
    null;

Future<void> _rosterSelect(WidgetTester tester, LibraryArtist artist) async {
  // From the first page, page by page.
  while (byKey('roster-tile-${artist.artistId}').evaluate().isEmpty &&
      _enabled(tester, 'roster-page-previous')) {
    await tester.tap(byKey('roster-page-previous'));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 10; i++) {
    final tile = byKey('roster-tile-${artist.artistId}');
    if (tile.evaluate().isNotEmpty) {
      // The fixture portraits never decode in a test, so the tile has no
      // height to tap: its own tap handler is called instead.
      tester
          .widget<InkWell>(
            find.descendant(of: tile, matching: find.byType(InkWell)),
          )
          .onTap!();
      await tester.pumpAndSettle();
      return;
    }
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
  }
  fail('${artist.name} not found in the Roster');
}

void main() {
  testWidgets('Roster -> Reel -> Roster keeps the selection and the reel '
      'never mixes artists', (tester) async {
    await _pump(tester, stats: _ImmediateStats());
    final madison = _named('Madison Beer');

    // Nothing chosen yet: Page 1, the first artist of the sorted roster
    // (App Update 1.1), Madison Beer by streams.
    _expectRosterShows(tester, madison);

    // Madison Beer (#1 by streams) is on the Roster's first page; visiting
    // the second page first saves a page.
    await tester.tap(byKey('roster-page-next'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-page-previous'));
    await tester.pumpAndSettle();
    await _rosterSelect(tester, madison);
    _expectRosterShows(tester, madison);

    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, madison);

    // Swiping on to another artist: everything follows the new portrait.
    await _reelNext(tester);
    final next = _artists[_artists.indexOf(madison) + 1];
    _expectReelShows(tester, next);

    await _switchTo(tester, LibraryView.roster);
    _expectRosterShows(tester, next);

    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, next);
  });

  testWidgets('a reel page saved on an earlier visit never wins over the '
      'selected artist (3Quency / Madison Beer)', (tester) async {
    await _pump(tester, stats: _ImmediateStats());
    final quency = _named('3Quency');
    final madison = _named('Madison Beer');

    // Earlier visit: the reel at 3Quency, the first artist A-Z.
    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, quency);
    await _reelNext(tester, times: 2);
    await tester.tap(byKey('film-reel-previous'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('film-reel-previous'));
    await tester.pumpAndSettle();
    _expectReelShows(tester, quency);

    // Madison Beer selected in the Roster.
    await _switchTo(tester, LibraryView.roster);
    _expectRosterShows(tester, quency);
    await _rosterSelect(tester, madison);
    _expectRosterShows(tester, madison);

    // Back in the reel: Madison Beer's portrait with Madison Beer's
    // statistics, never 3Quency's portrait with hers.
    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, madison);

    // Navigating from there stays consistent at every step.
    for (var i = 0; i < 3; i++) {
      await tester.tap(byKey('film-reel-previous'));
      await tester.pumpAndSettle();
      _expectReelShows(tester, _artists[_artists.indexOf(madison) - 1 - i]);
    }
  });

  testWidgets('rapid navigation in the reel: the statistics follow the '
      'portrait finally shown', (tester) async {
    await _pump(
      tester,
      stats: _ImmediateStats(),
      initialView: LibraryView.filmReel,
    );
    _expectReelShows(tester, _artists.first);

    // Several taps before any animation ends.
    for (var i = 0; i < 4; i++) {
      await tester.tap(byKey('film-reel-next'));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    final shown = _centredReelArtist(tester);
    _expectReelShows(tester, shown);

    // A fast fling across many artists.
    await tester.fling(byKey('film-reel-pages'), const Offset(0, -900), 4000);
    await tester.pumpAndSettle();
    _expectReelShows(tester, _centredReelArtist(tester));

    await tester.fling(byKey('film-reel-pages'), const Offset(0, 900), 4000);
    await tester.pumpAndSettle();
    _expectReelShows(tester, _centredReelArtist(tester));
  });

  testWidgets('a layout switch (compact and back) keeps the centred '
      'artist and their statistics together', (tester) async {
    await _pump(
      tester,
      stats: _ImmediateStats(),
      initialView: LibraryView.filmReel,
    );
    await _reelNext(tester, times: 3);
    _expectReelShows(tester, _artists[3]);

    // Short enough for the statistics to move under the reel.
    await tester.binding.setSurfaceSize(const Size(393, 480));
    await tester.pumpAndSettle();
    expect(byKey('film-reel-stats-below'), findsOneWidget);
    _expectReelShows(tester, _artists[3]);
    await _reelNext(tester, times: 2);
    _expectReelShows(tester, _artists[5]);

    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpAndSettle();
    expect(byKey('film-reel-stats-below'), findsNothing);
    _expectReelShows(tester, _artists[5]);

    // The Roster previews the same artist, on its page, in both layouts.
    await _switchTo(tester, LibraryView.roster);
    _expectRosterShows(tester, _artists[5]);
    await tester.binding.setSurfaceSize(const Size(393, 480));
    await tester.pumpAndSettle();
    expect(byKey('roster-compact'), findsOneWidget);
    expect(byKey('roster-tile-${_artists[5].artistId}'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpAndSettle();
    _expectRosterShows(tester, _artists[5]);
  });

  testWidgets('another Roster sort, before and after switching, keeps the '
      'same artist in both views', (tester) async {
    await _pump(tester, stats: _ImmediateStats());
    final wren = _named('Wren');

    // Newest first: Wren (added last) leads; selecting another artist on a
    // later page.
    await tester.tap(byKey('roster-sort'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-sort-recentlyAdded').last);
    await tester.pumpAndSettle();
    // A sort keeps the featured artist, still listed, on its new page
    // (App Update 1.1): the default, Madison Beer.
    _expectRosterShows(tester, _named('Madison Beer'));
    final ivo = _named('Ivo');
    await _rosterSelect(tester, ivo);
    _expectRosterShows(tester, ivo);

    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, ivo);
    await _reelNext(tester, times: 2);
    final kai = _named('Kai Lark');
    _expectReelShows(tester, kai);

    await _switchTo(tester, LibraryView.roster);
    _expectRosterShows(tester, kai);

    // Sorting A-Z after the switch follows the same artist.
    await tester.tap(byKey('roster-sort'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('roster-sort-name').last);
    await tester.pumpAndSettle();
    _expectRosterShows(tester, kai);
    await _rosterSelect(tester, wren);

    await _switchTo(tester, LibraryView.filmReel);
    _expectReelShows(tester, wren);
  });

  testWidgets('delayed statistics: a late result never shows for another '
      'artist, and a stale load never replaces a newer one', (tester) async {
    final stats = _GatedStats();
    final signal = LibraryChangeSignal();
    await _pump(
      tester,
      stats: stats,
      initialView: LibraryView.filmReel,
      signal: signal,
    );
    expect(stats.loads, hasLength(1));
    // Not loaded yet: dashes, never another artist's values.
    expect(_textIn(tester, byKey('film-reel-rank')), contains('–'));

    // The user moves on while the first load is still running.
    await _reelNext(tester, times: 3);
    final shown = _artists[3];
    expect(_centredReelArtist(tester).artistId, shown.artistId);
    expect(_textIn(tester, byKey('film-reel-rank')), contains('–'));

    // A library change asks for another load while the first runs.
    signal.notify(LibraryChangeKind.libraryEdited);
    await tester.pump(const Duration(milliseconds: 400));

    stats.loads[0].complete(_snapshot());
    await tester.pumpAndSettle();
    _expectReelShows(tester, shown);

    await _reelNext(tester);
    final later = _artists[4];
    expect(stats.loads, hasLength(2));
    stats.loads[1].complete(_snapshot(generation: 5));
    await tester.pumpAndSettle();
    _expectReelShows(tester, later, generation: 5);

    await _switchTo(tester, LibraryView.roster);
    expect(byKey('roster-header-${later.artistId}'), findsOneWidget);
  });

  test('a load answered out of order is dropped: the newest snapshot '
      'stays', () async {
    final loads = <Completer<ArtistLibraryStatisticsSnapshot>>[];
    final controller = ArtistReelStatisticsController(
      load: () {
        final completer = Completer<ArtistLibraryStatisticsSnapshot>();
        loads.add(completer);
        return completer.future;
      },
    );
    addTearDown(controller.dispose);

    unawaited(controller.refresh());
    unawaited(controller.refresh());
    await pumpEventQueue();
    expect(loads, hasLength(1), reason: 'loads never overlap');

    loads[0].complete(_snapshot(generation: 1));
    await pumpEventQueue();
    expect(loads, hasLength(2));
    loads[1].complete(_snapshot(generation: 2));
    await pumpEventQueue();

    final madison = _named('Madison Beer');
    expect(
      controller.snapshot[madison.artistId]!.qualifiedStreams,
      _statsOf(madison, generation: 2).qualifiedStreams,
    );
    for (final artist in _artists) {
      expect(controller.snapshot[artist.artistId]!.artistId, artist.artistId);
    }
  });

  testWidgets('a load from a replaced library answering late is never '
      'shown', (tester) async {
    final stale = _GatedStats();
    await _pump(tester, stats: stale, initialView: LibraryView.filmReel);
    expect(stale.loads, hasLength(1));

    // The library is replaced (new repository): a new controller loads.
    final fresh = _GatedStats();
    await _pump(
      tester,
      stats: fresh,
      repository: base.FakeLibraryQueryRepository(artists: _artists),
      initialView: LibraryView.filmReel,
    );
    expect(fresh.loads, hasLength(1));
    fresh.loads[0].complete(_snapshot(generation: 9));
    await tester.pumpAndSettle();
    _expectReelShows(tester, _artists.first, generation: 9);

    // The old load answers last; it must not replace the new values.
    stale.loads[0].complete(_snapshot(generation: 1));
    await tester.pumpAndSettle();
    _expectReelShows(tester, _artists.first, generation: 9);
  });
}
