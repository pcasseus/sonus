// App Update 1.3 (post-preview): the playlist song picker browses the
// library as Songs, Artists or Albums, A–Z with the shared letter rail,
// with one selection across every mode, group and search. Fictional
// fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_image.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/playlists/application/models/playlist_add_result.dart';
import 'package:sonus_next/features/playlists/presentation/controllers/playlist_song_picker_controller.dart';
import 'package:sonus_next/features/playlists/presentation/pages/playlist_song_picker_page.dart';

LibraryTrack _track(
  String id, {
  String? title,
  String artist = 'Nova',
  String? artistId,
  String album = 'First Light',
  String? albumId,
  String? edition,
  int disc = 1,
  int number = 1,
  String? artworkPath,
  String? versionLabel,
  bool available = true,
  bool blocked = false,
}) => LibraryTrack(
  songId: id,
  title: title ?? 'Song $id',
  artistId: artistId ?? 'artist-$artist',
  artistName: artist,
  albumId: albumId ?? 'album-$album',
  albumTitle: album,
  albumEditionId: edition ?? 'edition-$album',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.values.first,
  trackNumber: number,
  discNumber: disc,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  versionLabel: versionLabel,
  artworkPath: artworkPath,
  dateAdded: DateTime(2026, 1, 1),
  filePath: '/music/$id.mp3',
  isAvailable: available,
  isSongBlocked: blocked,
);

/// A spread across the alphabet, '#' titles, three artists and releases.
List<LibraryTrack> _library() => [
  _track('s-2', title: '2 Become 1', artist: 'Zola', album: 'Numbers'),
  _track('s-hash', title: '#hashtag', artist: 'Zola', album: 'Numbers'),
  _track('s-apple', title: 'apple', artist: 'Ava', album: 'Orchard', number: 2),
  _track('s-banana', title: 'Banana', artist: 'Ava', album: 'Orchard'),
  _track('s-elan', title: 'Élan', artist: 'Nova', album: 'First Light'),
  _track('s-zed', title: 'Zed', artist: 'Nova', album: 'First Light'),
  _track('s-off', title: 'Offline', available: false),
  _track('s-blocked', title: 'Blocked', blocked: true),
];

PlaylistSongPickerController _controller({
  List<LibraryTrack>? tracks,
  Set<String> inPlaylist = const {},
  List<List<String>>? added,
}) => PlaylistSongPickerController(
  loadTracks: () async => tracks ?? _library(),
  songIdsInPlaylist: inPlaylist,
  add: (ids) async {
    added?.add(ids);
    return PlaylistAddResult(
      playlistName: 'Car',
      added: ids.length,
      alreadyPresent: 0,
      failed: 0,
    );
  },
);

List<String> _ids(Iterable<LibraryTrack> tracks) => [
  for (final track in tracks) track.songId,
];

Finder _key(String value) => find.byKey(ValueKey<String>(value));

void main() {
  group('controller', () {
    test('Songs: A–Z with "#" first and accents filed under their letter; '
        'unplayable and blocked songs are not offered', () async {
      final c = _controller();
      await c.load();
      expect(_ids(c.visibleTracks), [
        's-hash',
        's-2',
        's-apple',
        's-banana',
        's-elan',
        's-zed',
      ]);
    });

    test('a song on several editions is offered once', () async {
      final c = _controller(
        tracks: [
          _track('same', edition: 'standard'),
          _track('same', edition: 'deluxe'),
        ],
      );
      await c.load();
      expect(_ids(c.visibleTracks), ['same']);
    });

    test('Artists and Albums: A–Z groups by library identity; a release '
        'lists its songs by disc and track and shows its own cover', () async {
      final c = _controller(
        tracks:
            [
                  ..._library(),
                  _track(
                    's-cherry',
                    title: 'Cherry',
                    artist: 'Ava',
                    album: 'Orchard',
                    disc: 2,
                    artworkPath: '/art/own-cherry.png',
                  ),
                  // Another artist with the same name stays separate.
                  _track(
                    's-other',
                    title: 'Other',
                    artist: 'Ava',
                    artistId: 'ava-2',
                  ),
                ]
                .map(
                  (t) => t.albumTitle == 'Orchard' && t.songId != 's-cherry'
                      ? _track(
                          t.songId,
                          title: t.title,
                          artist: 'Ava',
                          album: 'Orchard',
                          number: t.trackNumber,
                          artworkPath: '/art/orchard.png',
                        )
                      : t,
                )
                .toList(),
      );
      await c.load();

      c.setMode(PlaylistPickerMode.artists);
      expect(
        [for (final g in c.visibleGroups) g.id],
        ['artist-Ava', 'ava-2', 'artist-Nova', 'artist-Zola'],
      );
      expect(_ids(c.visibleGroups.first.tracks), [
        's-apple',
        's-banana',
        's-cherry',
      ]);

      c.setMode(PlaylistPickerMode.albums);
      final orchard = c.visibleGroups.firstWhere((g) => g.title == 'Orchard');
      expect(_ids(orchard.tracks), ['s-banana', 's-apple', 's-cherry']);
      expect(orchard.detail, 'Ava');
      expect(orchard.artworkPath, '/art/orchard.png');
    });

    test('one selection across modes, groups and searches; Select all '
        'skips songs already in the playlist and toggles back', () async {
      final added = <List<String>>[];
      final c = _controller(inPlaylist: {'s-banana'}, added: added);
      await c.load();

      c.toggle('s-zed');
      c.setMode(PlaylistPickerMode.artists);
      c.openGroupById('artist-Ava');
      c.toggleAll(c.openGroup!.tracks);
      expect(c.selectedCount, 2, reason: 'Banana is already in the playlist');
      expect(c.allSelected(c.openGroup!.tracks), isTrue);

      c.closeGroup();
      c.setMode(PlaylistPickerMode.albums);
      c.search('numbers');
      c.openGroupById('album-Numbers');
      c.toggle('s-2');
      c.search('');
      c.setMode(PlaylistPickerMode.songs);

      expect(c.selectedCount, 3);
      for (final id in ['s-zed', 's-apple', 's-2']) {
        expect(c.isSelected(id), isTrue, reason: id);
      }

      c.setMode(PlaylistPickerMode.artists);
      c.openGroupById('artist-Ava');
      c.toggleAll(c.openGroup!.tracks);
      expect(c.isSelected('s-apple'), isFalse);
      expect(c.selectedCount, 2);

      await c.addSelected();
      expect(added, [
        ['s-zed', 's-2'],
      ]);
    });

    test('search filters groups too; an open group with no match stays '
        'open and empty', () async {
      final c = _controller();
      await c.load();
      c.setMode(PlaylistPickerMode.artists);
      c.search('orchard');
      expect([for (final g in c.visibleGroups) g.title], ['Ava']);

      c.openGroupById('artist-Ava');
      c.search('zzz');
      expect(c.openGroup?.title, 'Ava');
      expect(c.visibleTracks, isEmpty);
    });
  });

  group('page', () {
    Future<PlaylistSongPickerController> open(
      WidgetTester tester, {
      List<LibraryTrack>? tracks,
      Set<String> inPlaylist = const {},
      List<List<String>>? added,
      Size size = const Size(411, 900),
      double textScale = 1,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      if (textScale != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final controller = _controller(
        tracks: tracks,
        inPlaylist: inPlaylist,
        added: added,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: PlaylistSongPickerPage(
            playlistName: 'Car',
            controller: controller,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      return controller;
    }

    /// 26 songs per letter, A to Z, plus some '#' titles.
    List<LibraryTrack> big() => [
      for (var i = 0; i < 20; i++) _track('n$i', title: '$i Numbers'),
      for (final letter in 'ABCDEFGHIJKLMNOPRSTUVWXYZ'.split(''))
        for (var i = 0; i < 26; i++)
          _track(
            '$letter$i',
            title: '$letter song ${i.toString().padLeft(2, '0')}',
            artist: '$letter Artist',
            album: '$letter Album',
            number: i + 1,
            artworkPath: i.isEven ? '/art/$letter.png' : null,
          ),
    ];

    Future<void> mode(WidgetTester tester, PlaylistPickerMode mode) async {
      // At large text on a narrow phone the modes scroll sideways.
      await tester.ensureVisible(_key('song-picker-mode-${mode.name}'));
      await tester.pumpAndSettle();
      await tester.tap(_key('song-picker-mode-${mode.name}'));
      await tester.pumpAndSettle();
    }

    double listTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ListView).last).dy;

    testWidgets('tapping a letter brings its first song to the top', (
      tester,
    ) async {
      await open(tester, tracks: big());
      await tester.tap(_key('alphabet-rail-M'));
      await tester.pumpAndSettle();

      final row = tester.getRect(_key('song-picker-row-M0'));
      expect(row.top, closeTo(listTop(tester), 1));
    });

    testWidgets('a letter with no songs (Q) goes to the next one that has '
        'songs, and is drawn dimmed', (tester) async {
      await open(tester, tracks: big());
      final q = tester.widget<Text>(_key('alphabet-rail-Q')).style!.color!;
      final r = tester.widget<Text>(_key('alphabet-rail-R')).style!.color!;
      expect(q.a, lessThan(r.a));

      await tester.tap(_key('alphabet-rail-Q'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_key('song-picker-row-R0')).top,
        closeTo(listTop(tester), 1),
      );
    });

    testWidgets('dragging along the rail shows the large letter and lands '
        'where it is released', (tester) async {
      await open(tester, tracks: big());
      final gesture = await tester.startGesture(
        tester.getCenter(_key('alphabet-rail-B')),
      );
      await gesture.moveTo(tester.getCenter(_key('alphabet-rail-G')));
      await tester.pump();
      expect(_key('alphabet-scrub-bubble'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(_key('alphabet-rail-T')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_key('alphabet-scrub-bubble'), findsNothing);
      expect(
        tester.getRect(_key('song-picker-row-T0')).top,
        closeTo(listTop(tester), 1),
      );
    });

    testWidgets('"#" holds titles starting with a digit or symbol', (
      tester,
    ) async {
      await open(tester, tracks: big());
      await tester.tap(_key('alphabet-rail-Z'));
      await tester.pumpAndSettle();
      await tester.tap(_key('alphabet-rail-#'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_key('song-picker-row-n0')).top,
        closeTo(listTop(tester), 1),
      );
    });

    testWidgets('the rail covers no checkbox, cover or title', (tester) async {
      await open(tester, tracks: big());
      final rail = tester.getRect(find.byKey(const ValueKey('alphabet-rail')));
      for (final part in [
        find.descendant(
          of: _key('song-picker-row-n0'),
          matching: find.byType(Checkbox),
        ),
        _key('song-picker-artwork-n0'),
        // The whole area the cover and title text may use.
        find
            .ancestor(
              of: _key('song-picker-artwork-n0'),
              matching: find.byType(Row),
            )
            .first,
      ]) {
        expect(tester.getRect(part).right, lessThanOrEqualTo(rail.left));
      }
    });

    testWidgets('letters follow the mode: Artists and Albums jump by '
        'artist and release name', (tester) async {
      await open(tester, tracks: big());
      await mode(tester, PlaylistPickerMode.artists);
      expect(_key('song-picker-rail-artists'), findsOneWidget);
      await tester.tap(_key('alphabet-rail-K'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_key('song-picker-group-artist-K Artist')).top,
        closeTo(listTop(tester), 1),
      );

      await mode(tester, PlaylistPickerMode.albums);
      await tester.tap(_key('alphabet-rail-J'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_key('song-picker-group-album-J Album')).top,
        closeTo(listTop(tester), 1),
      );
    });

    testWidgets('an artist opens their songs; Select all, back, another '
        'artist, Songs: every choice is kept and counted', (tester) async {
      await open(tester, tracks: _library(), inPlaylist: {'s-banana'});
      await tester.tap(_key('song-picker-row-s-zed'));
      await tester.pump();

      await mode(tester, PlaylistPickerMode.artists);
      expect(
        find.descendant(
          of: _key('song-picker-group-artist-Nova'),
          matching: find.textContaining('1 selected'),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('song-picker-group-artist-Ava'));
      await tester.pumpAndSettle();
      expect(find.text('Ava'), findsWidgets);
      await tester.tap(_key('song-picker-select-all'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);

      await tester.tap(_key('song-picker-group-back'));
      await tester.pumpAndSettle();
      await tester.tap(_key('song-picker-group-artist-Zola'));
      await tester.pumpAndSettle();
      await tester.tap(_key('song-picker-row-s-2'));
      await tester.pump();

      await mode(tester, PlaylistPickerMode.songs);
      expect(find.text('3 selected'), findsOneWidget);
      for (final id in ['s-zed', 's-apple', 's-2']) {
        expect(
          tester.widget<CheckboxListTile>(_key('song-picker-row-$id')).value,
          isTrue,
          reason: id,
        );
      }
    });

    testWidgets('an album shows its cover and opens its songs in track '
        'order; one song or all of them', (tester) async {
      final tracks = [
        _track(
          'o-2',
          title: 'Second',
          album: 'Orchard',
          number: 2,
          artworkPath: '/art/orchard.png',
        ),
        _track(
          'o-1',
          title: 'First',
          album: 'Orchard',
          number: 1,
          artworkPath: '/art/orchard.png',
        ),
        _track('x', title: 'Elsewhere', album: 'Another'),
      ];
      await open(tester, tracks: tracks);
      await mode(tester, PlaylistPickerMode.albums);
      expect(
        tester
            .widget<SonusArtworkImage>(
              _key('song-picker-group-artwork-album-Orchard'),
            )
            .path,
        '/art/orchard.png',
      );
      await tester.tap(_key('song-picker-group-album-Orchard'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_key('song-picker-row-o-1')).dy,
        lessThan(tester.getTopLeft(_key('song-picker-row-o-2')).dy),
      );
      await tester.tap(_key('song-picker-row-o-2'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(_key('song-picker-select-all'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(_key('song-picker-select-all'));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('searching while songs are chosen keeps them; no match '
        'says so in every mode', (tester) async {
      await open(tester, tracks: _library());
      await tester.tap(_key('song-picker-row-s-apple'));
      await tester.pump();
      await tester.enterText(_key('song-picker-search'), 'zed');
      await tester.pump();
      expect(_key('song-picker-row-s-apple'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);

      await tester.enterText(_key('song-picker-search'), 'nothing here');
      await tester.pump();
      for (final m in PlaylistPickerMode.values) {
        await mode(tester, m);
        expect(find.textContaining('No songs match'), findsOneWidget);
      }

      await tester.tap(_key('song-picker-search-clear'));
      await mode(tester, PlaylistPickerMode.songs);
      expect(
        tester.widget<CheckboxListTile>(_key('song-picker-row-s-apple')).value,
        isTrue,
      );
    });

    testWidgets('Back closes an open artist first; then the picker closes '
        'without adding anything', (tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final added = <List<String>>[];
      PlaylistSongPickerResult? result;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await PlaylistSongPickerPage.open(
                  context,
                  playlistName: 'Car',
                  songIdsInPlaylist: const {},
                  loadTracks: () async => _library(),
                  add: (ids) async {
                    added.add(ids);
                    return PlaylistAddResult(
                      playlistName: 'Car',
                      added: ids.length,
                      alreadyPresent: 0,
                      failed: 0,
                    );
                  },
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(_key('song-picker-row-s-zed'));
      await mode(tester, PlaylistPickerMode.artists);
      await tester.tap(_key('song-picker-group-artist-Ava'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_key('playlist-song-picker'), findsOneWidget);
      expect(_key('song-picker-group-artist-Ava'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(added, isEmpty);
    });

    testWidgets('a large library: rows are built lazily and Z is reached '
        'at once', (tester) async {
      final tracks = [
        for (var i = 0; i < 3000; i++)
          _track(
            'big$i',
            title:
                '${String.fromCharCode(65 + i % 26)} title '
                '${i.toString().padLeft(4, '0')}',
            artist: 'Artist ${i % 40}',
            album: 'Album ${i % 120}',
          ),
      ];
      await open(tester, tracks: tracks);
      expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
      await tester.tap(_key('alphabet-rail-Z'));
      await tester.pumpAndSettle();
      expect(find.text('Z title 0025'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final m in PlaylistPickerMode.values) {
      testWidgets('320 px at 2x text, ${m.label}, with a group open and a '
          'long versioned title', (tester) async {
        await open(
          tester,
          tracks: [
            ..._library(),
            _track(
              'long',
              title: 'A very long song title that keeps going and going',
              versionLabel: 'Acoustic Remix',
              artist: 'An Artist With A Long Name',
              album: 'A Release With A Long Name',
            ),
          ],
          size: const Size(320, 700),
          textScale: 2,
        );
        await mode(tester, m);
        expect(tester.takeException(), isNull);
        if (m != PlaylistPickerMode.songs) {
          await tester.tap(find.byType(ListTile).first);
          await tester.pumpAndSettle();
          expect(_key('song-picker-select-all'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('TalkBack: the rail is an adjustable "Jump to letter"; '
        'groups and Select all name what they do', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, tracks: _library());
      final rail = tester.getSemantics(
        find.byKey(const ValueKey('alphabet-rail')),
      );
      expect(rail.label, 'Jump to letter');
      expect(
        rail.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );

      await mode(tester, PlaylistPickerMode.artists);
      expect(
        tester.getSemantics(_key('song-picker-group-artist-Ava')).label,
        allOf(contains('Ava'), contains('2 songs')),
      );
      await tester.tap(_key('song-picker-group-artist-Ava'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Select all songs in Ava'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('with the keyboard open the search and Add bar stay '
        'usable; the Add bar clears the navigation area', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 48 * 3);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48 * 3);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await open(tester, tracks: _library());
      const screen = 900.0;
      expect(
        tester.getRect(_key('song-picker-add')).bottom,
        lessThanOrEqualTo(screen - 48),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(_key('song-picker-search'));
      await tester.enterText(_key('song-picker-search'), 'a');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_key('song-picker-search'), findsOneWidget);
      expect(find.text('0 selected'), findsOneWidget);
    });
  });
}
