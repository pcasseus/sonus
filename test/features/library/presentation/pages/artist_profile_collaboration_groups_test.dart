import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/library/presentation/widgets/artist_profile/artist_profile_tracks_list.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';

import 'artist_profile_page_test.dart' as base;

// SN-51 C1 (D9): collaborations from one release (album id) show as one
// expandable entry. Fictional fixtures only.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<LibraryTrack> collaborations,
    PlaybackCoordinator? playbackCoordinator,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 3000),
    double textScale = 1,
    bool disableAnimations = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = base.FakeLibraryQueryRepository(
      artist: base.createArtist(),
      albums: [base.createAlbum()],
      tracks: [base.createTrack(songId: 'own', title: 'Own Song')],
      allTracks: [
        base.createTrack(songId: 'own', title: 'Own Song'),
        ...collaborations,
      ],
    );

    await tester.pumpWidget(
      base.buildSubject(
        repository: repository,
        playbackCoordinator: playbackCoordinator,
        theme: SonusThemeFactory.build(spec),
        appBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: const ArtistProfilePage(
          artistId: 'artist-1',
          initialArtistName: 'Test Artist',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A song of the profile's artist featured on someone else's release.
  LibraryTrack guest(
    String songId, {
    required String albumId,
    String albumTitle = 'Their Album',
    String? primaryEditionTitle,
    String editionId = 'edition-1',
    String editionTitle = 'Standard',
    String? title,
  }) {
    return LibraryTrack(
      songId: songId,
      title: title ?? 'Song $songId',
      artistId: 'other-artist',
      artistName: 'Other Fixture',
      albumId: albumId,
      albumTitle: albumTitle,
      primaryEditionTitle: primaryEditionTitle,
      albumEditionId: editionId,
      albumEditionTitle: editionTitle,
      albumEditionType: AlbumEditionType.values.first,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const ['Test Artist'],
      dateAdded: DateTime(2026, 1, 1),
      filePath: '/music/$songId.mp3',
      isAvailable: true,
    );
  }

  Finder albumGroup(String albumId) =>
      find.byKey(ValueKey<String>('artist-collaboration-group-$albumId'));
  Finder header(String albumId) => find.byKey(
    ValueKey<String>('artist-collaboration-group-$albumId-header'),
  );
  Finder row(String songId) =>
      find.byKey(ValueKey<String>('artist-track-$songId'));

  group('grouping', () {
    test('keys groups by album id, keeping order', () {
      final tracks = [
        guest('a1', albumId: 'alpha'),
        guest('b1', albumId: 'beta'),
        guest('a2', albumId: 'alpha'),
      ];
      final groups = ArtistProfileTracksList.albumGroups(tracks);
      expect(
        [
          for (final group in groups) [for (final t in group) t.songId],
        ],
        [
          ['a1', 'a2'],
          ['b1'],
        ],
      );
    });

    testWidgets('two releases with the same title stay separate', (
      tester,
    ) async {
      await pump(
        tester,
        collaborations: [
          guest('x1', albumId: 'release-x', albumTitle: 'Same Title'),
          guest('x2', albumId: 'release-x', albumTitle: 'Same Title'),
          guest('y1', albumId: 'release-y', albumTitle: 'Same Title'),
          guest('y2', albumId: 'release-y', albumTitle: 'Same Title'),
        ],
      );

      expect(albumGroup('release-x'), findsOneWidget);
      expect(albumGroup('release-y'), findsOneWidget);
      expect(find.text('Same Title'), findsNWidgets(2));
      expect(find.text('2 collaborations'), findsNWidgets(2));
    });

    testWidgets('one album id with different titles and editions stays one '
        'group', (tester) async {
      await pump(
        tester,
        collaborations: [
          guest(
            'std',
            albumId: 'release-z',
            albumTitle: 'Night Drive',
            primaryEditionTitle: 'Night Drive',
          ),
          guest(
            'dlx',
            albumId: 'release-z',
            albumTitle: 'Night Drive (Deluxe)',
            primaryEditionTitle: 'Night Drive',
            editionId: 'edition-deluxe',
            editionTitle: 'Night Drive (Deluxe)',
          ),
        ],
      );

      expect(albumGroup('release-z'), findsOneWidget);
      expect(find.text('2 collaborations'), findsOneWidget);
      expect(row('std'), findsNothing);
      expect(row('dlx'), findsNothing);
    });

    testWidgets('a single collaboration stays a plain row', (tester) async {
      await pump(
        tester,
        collaborations: [
          guest('solo', albumId: 'solo-release', albumTitle: 'Solo Release'),
          guest('p1', albumId: 'pair', albumTitle: 'Pair'),
          guest('p2', albumId: 'pair', albumTitle: 'Pair'),
        ],
      );

      expect(albumGroup('solo-release'), findsNothing);
      expect(row('solo'), findsOneWidget);
      expect(
        find.descendant(
          of: row('solo'),
          matching: find.textContaining('Solo Release'),
        ),
        findsOneWidget,
      );
      expect(albumGroup('pair'), findsOneWidget);
    });

    testWidgets('the section count stays the number of songs', (tester) async {
      await pump(
        tester,
        collaborations: [
          guest('p1', albumId: 'pair'),
          guest('p2', albumId: 'pair'),
          guest('solo', albumId: 'solo'),
        ],
      );

      final heading = find.byKey(
        const ValueKey<String>('artist-profile-collaborations'),
      );
      expect(
        find.descendant(of: heading, matching: find.text('3')),
        findsOneWidget,
      );
    });
  });

  group('expanding', () {
    final collaborations = [
      guest('a1', albumId: 'alpha', albumTitle: 'Alpha', title: 'A One'),
      guest('a2', albumId: 'alpha', albumTitle: 'Alpha', title: 'A Two'),
      guest('b1', albumId: 'beta', albumTitle: 'Beta', title: 'B One'),
      guest('c1', albumId: 'gamma', albumTitle: 'Gamma', title: 'C One'),
      guest('c2', albumId: 'gamma', albumTitle: 'Gamma', title: 'C Two'),
    ];

    testWidgets('expand shows the songs, collapse hides them', (tester) async {
      await pump(tester, collaborations: collaborations);

      expect(row('a1'), findsNothing);
      await tester.tap(header('alpha'));
      await tester.pumpAndSettle();
      expect(row('a1'), findsOneWidget);
      expect(row('a2'), findsOneWidget);
      // The header names the release; the rows do not repeat it.
      for (final id in ['a1', 'a2']) {
        expect(
          find.descendant(
            of: row(id),
            matching: find.textContaining('Other Fixture'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row(id), matching: find.textContaining('Alpha')),
          findsNothing,
        );
      }
      expect(row('c1'), findsNothing);

      await tester.tap(header('alpha'));
      await tester.pumpAndSettle();
      expect(row('a1'), findsNothing);
    });

    testWidgets('a song inside a group queues all collaborations as before', (
      tester,
    ) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        collaborations: collaborations,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(header('gamma'));
      await tester.pumpAndSettle();
      await tester.tap(row('c2'));
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((t) => t.songId), [
        'a1',
        'a2',
        'b1',
        'c1',
        'c2',
      ]);
      expect(engine.lastStartIndex, 4);

      await tester.tap(row('b1'));
      await tester.pump();
      expect(engine.lastStartIndex, 2);
      await engine.dispose();
    });

    testWidgets('songs inside a group keep their menu', (tester) async {
      await pump(tester, collaborations: collaborations);

      await tester.tap(header('alpha'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('artist-track-menu-a2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Go to album'), findsOneWidget);
      expect(find.text('Play next'), findsOneWidget);
    });

    testWidgets('reduced motion opens at once, without animating', (
      tester,
    ) async {
      await pump(
        tester,
        collaborations: collaborations,
        spec: const SonusAppearanceSpec(reduceMotion: true),
      );

      expect(
        find.descendant(
          of: albumGroup('alpha'),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      await tester.tap(header('alpha'));
      await tester.pump();
      // Full height on the first frame: nothing grows into place.
      expect(tester.getSize(row('a1')).height, greaterThanOrEqualTo(48));
    });

    testWidgets('system animations off opens at once', (tester) async {
      await pump(
        tester,
        collaborations: collaborations,
        disableAnimations: true,
      );

      expect(
        find.descendant(
          of: albumGroup('alpha'),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      await tester.tap(header('alpha'));
      await tester.pump();
      expect(row('a2'), findsOneWidget);
    });

    testWidgets('fits 320dp at 2x text, collapsed and expanded', (
      tester,
    ) async {
      await pump(
        tester,
        collaborations: [
          guest(
            'l1',
            albumId: 'long',
            albumTitle: 'A Release With An Unusually Long Name For Wrapping',
            title: 'An Unusually Long Collaboration Title For Wrapping',
          ),
          guest(
            'l2',
            albumId: 'long',
            albumTitle: 'A Release With An Unusually Long Name For Wrapping',
          ),
        ],
        size: const Size(320, 4000),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(header('long'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(row('l1'), findsOneWidget);
    });

    testWidgets('the header is a 48dp button announcing its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, collaborations: collaborations);

      expect(tester.getSize(header('alpha')).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(header('alpha')),
        matchesSemantics(
          label: 'Alpha, 2 collaborations',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(header('alpha'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(header('alpha')),
        matchesSemantics(
          label: 'Alpha, 2 collaborations',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
