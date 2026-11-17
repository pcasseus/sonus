// Horizontal rails start at their first item (App Update 1.3 follow-up).
//
// The bug: a horizontal scroll view without its own controller kept its
// offset in PageStorage under the page's slot, so a rail on a scrolled page
// reopened at the page's vertical offset (mid-rail or at the end), and one
// rail's scrolling overwrote another's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/sonus_horizontal_rail.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';
import 'package:sonus_next/features/library/presentation/widgets/artist_profile/artist_profile_albums_grid.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

LibraryAlbum _album(String id) => LibraryAlbum(
  albumId: id,
  title: 'Album $id',
  artistId: 'artist',
  artistName: 'Artist',
  trackCount: 10,
  dateAdded: DateTime.utc(2026, 9, 1),
);

List<ArtistRailCard> _cards(String prefix, int count) => [
  for (var i = 0; i < count; i++)
    ArtistReleaseCard(album: _album('$prefix$i'), format: null),
];

/// A page like an Artist Profile: a vertical list with its own PageStorage
/// slot, scrolled down, holding [rails].
class _Page extends StatelessWidget {
  const _Page({required this.storageKey, required this.rails});

  final String storageKey;
  final List<Widget> rails;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        key: PageStorageKey<String>(storageKey),
        children: [
          const SizedBox(height: 900),
          for (final rail in rails) ...[rail, const SizedBox(height: 40)],
          const SizedBox(height: 1600),
        ],
      ),
    );
  }
}

Widget _grid(List<ArtistRailCard> cards, {Key? key}) =>
    ArtistProfileAlbumsGrid(key: key, cards: cards, onAlbumTap: (_) {});

ScrollPosition _railPosition(WidgetTester tester, Finder rail) => tester
    .state<ScrollableState>(
      find.descendant(of: rail, matching: find.byType(Scrollable)).first,
    )
    .position;

Future<void> _scrollPage(WidgetTester tester, double offset) async {
  final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
  page.position.jumpTo(offset);
  await tester.pump();
}

void main() {
  testWidgets('an Artist Profile rail reopens at its first card even when '
      'the page was scrolled (the reported bug)', (tester) async {
    final bucket = PageStorageBucket();
    Widget app({required bool show}) => MaterialApp(
      home: PageStorage(
        bucket: bucket,
        child: show
            ? _Page(storageKey: 'artist-page', rails: [_grid(_cards('a', 12))])
            : const SizedBox(),
      ),
    );

    await tester.pumpWidget(app(show: true));
    await _scrollPage(tester, 700);
    final rail = _key('artist-profile-albums-grid');
    expect(_railPosition(tester, rail).pixels, 0);

    // Leave the page and come back: the page restores its own offset, the
    // rail starts at its first card, not at the page's offset.
    await tester.pumpWidget(app(show: false));
    await tester.pumpWidget(app(show: true));
    await tester.pumpAndSettle();
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(page.position.pixels, 700, reason: 'the page keeps its place');
    expect(_railPosition(tester, rail).pixels, 0);
    expect(tester.getTopLeft(_key('artist-album-a0')).dx, 0);
  });

  testWidgets('switching to another artist starts every rail at its first '
      'card, with no frame at the old offset', (tester) async {
    Widget page(String artist) => MaterialApp(
      home: _Page(
        storageKey: 'artist-page',
        rails: [_grid(_cards(artist, 12))],
      ),
    );
    await tester.pumpWidget(page('a'));
    await _scrollPage(tester, 700);
    final rail = _key('artist-profile-albums-grid');
    _railPosition(tester, rail).jumpTo(500);
    await tester.pump();

    await tester.pumpWidget(page('b'));
    // The very first frame of the new artist is already at the start.
    expect(_railPosition(tester, rail).pixels, 0);
    expect(tester.getTopLeft(_key('artist-album-b0')).dx, 0);
  });

  testWidgets('returning from a detail page keeps the rail where it was', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: _Page(storageKey: 'artist-page', rails: [_grid(_cards('a', 12))]),
      ),
    );
    await _scrollPage(tester, 700);
    final rail = _key('artist-profile-albums-grid');
    _railPosition(tester, rail).jumpTo(420);
    await tester.pump();

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_railPosition(tester, rail).pixels, 420);
  });

  testWidgets('a refresh with the same cards keeps the position; a new order '
      'starts over', (tester) async {
    Widget page(List<ArtistRailCard> cards) => MaterialApp(
      home: _Page(storageKey: 'artist-page', rails: [_grid(cards)]),
    );
    final cards = _cards('a', 12);
    await tester.pumpWidget(page(cards));
    await _scrollPage(tester, 700);
    final rail = _key('artist-profile-albums-grid');
    _railPosition(tester, rail).jumpTo(300);
    await tester.pump();

    await tester.pumpWidget(page([...cards]));
    expect(_railPosition(tester, rail).pixels, 300, reason: 'same rail');

    await tester.pumpWidget(page(cards.reversed.toList()));
    expect(_railPosition(tester, rail).pixels, 0, reason: 'reordered');
  });

  testWidgets('rails on one page never share or overwrite each other', (
    tester,
  ) async {
    // Tall enough for all three rails to be built.
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: _Page(
          storageKey: 'artist-page',
          rails: [
            _grid(_cards('albums', 12), key: const ValueKey('albums')),
            _grid(_cards('singles', 12), key: const ValueKey('singles')),
            _grid(_cards('live', 2), key: const ValueKey('live')),
          ],
        ),
      ),
    );
    await _scrollPage(tester, 700);
    ScrollPosition at(String key) => _railPosition(tester, _key(key));

    at('albums').jumpTo(250);
    await tester.pump();
    expect(at('singles').pixels, 0);
    expect(at('live').pixels, 0);
    // A short rail does not scroll and sits at the start.
    expect(at('live').maxScrollExtent, 0);
  });

  testWidgets('an empty rail that loads later starts at its first card', (
    tester,
  ) async {
    Widget page(List<ArtistRailCard> cards) => MaterialApp(
      home: _Page(storageKey: 'artist-page', rails: [_grid(cards)]),
    );
    await tester.pumpWidget(page(const []));
    await _scrollPage(tester, 700);
    await tester.pumpWidget(page(_cards('a', 12)));
    await tester.pumpAndSettle();
    expect(_railPosition(tester, _key('artist-profile-albums-grid')).pixels, 0);
  });

  testWidgets('a rail never writes to or reads from PageStorage', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    late ScrollController seen;
    await tester.pumpWidget(
      MaterialApp(
        home: PageStorage(
          bucket: bucket,
          child: Scaffold(
            body: SonusHorizontalRail(
              identity: 'rail',
              builder: (context, controller) {
                seen = controller;
                return ListView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(width: 120, child: Text('$i')),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(seen.keepScrollOffset, isFalse);
    seen.jumpTo(600);
    await tester.pump();
    final context = tester.element(find.byType(Scrollable));
    expect(bucket.readState(context), isNull);
  });
}
