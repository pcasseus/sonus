import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/album_studio_page.dart';

import 'album_profile_page_test.dart' as base;

// SN-48J J4: the Album Studio layout.
void main() {
  LibraryTrack track(String id, int number, {int disc = 1, String? edition}) =>
      base.createTrack(
        songId: id,
        title: 'Song $id',
        albumEditionId: edition ?? 'edition-standard',
        albumEditionTitle: edition == 'edition-deluxe' ? 'Deluxe' : 'Standard',
        albumEditionType: edition == 'edition-deluxe'
            ? AlbumEditionType.deluxe
            : AlbumEditionType.standard,
        trackNumber: number,
        discNumber: disc,
      );

  base.FakeEditionAwareLibraryQueryRepository repository({
    int count = 20,
    bool deluxe = false,
    List<LibraryTrack>? tracks,
  }) => base.FakeEditionAwareLibraryQueryRepository(
    album: base.createAlbum(
      title: 'Studio Album',
      primaryEditionId: 'edition-standard',
      primaryEditionTitle: 'Standard',
    ),
    editions: [
      base.createLibraryEdition(
        editionId: 'edition-standard',
        title: 'Standard',
        type: AlbumEditionType.standard,
        isPrimary: true,
      ),
      if (deluxe)
        base.createLibraryEdition(
          editionId: 'edition-deluxe',
          title: 'Deluxe',
          type: AlbumEditionType.deluxe,
        ),
    ],
    editionTracks: {
      'edition-standard':
          tracks ?? [for (var n = 1; n <= count; n++) track('s$n', n)],
      if (deluxe)
        'edition-deluxe': [
          track('s1', 1, edition: 'edition-deluxe'),
          track('bonus', 2, edition: 'edition-deluxe'),
        ],
    },
  );

  Future<(AlbumProfileController, base.FakeAlbumEditionTrackOrderingService)>
  pump(
    WidgetTester tester, {
    base.FakeEditionAwareLibraryQueryRepository? repo,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 800),
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    Future<void> Function()? onChangeArtwork,
    Future<void> Function()? onClearArtwork,
    Future<void> Function()? onEditDetails,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ordering = base.FakeAlbumEditionTrackOrderingService();
    final controller = AlbumProfileController(
      repository: repo ?? repository(),
      albumId: 'album-1',
      albumEditionTrackOrderingService: ordering,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(spec),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: padding,
          ),
          child: child!,
        ),
        home: AlbumStudioPage(
          controller: controller,
          userId: null,
          onEditDetails: onEditDetails,
          onChangeArtwork: onChangeArtwork,
          onClearArtwork: onClearArtwork,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, ordering);
  }

  Finder tool(String key) => find.byKey(ValueKey<String>('album-studio-$key'));

  group('layout', () {
    // Regression (J4): a fixed tools card above the list left about three
    // track rows visible on a phone.
    testWidgets('tracks get the screen: tools start collapsed', (tester) async {
      await pump(tester);

      expect(tool('edit-details'), findsNothing);
      final visible = [
        for (var n = 1; n <= 20; n++)
          if (find
              .byKey(ValueKey<String>('album-studio-track-s$n'))
              .hitTestable()
              .evaluate()
              .isNotEmpty)
            n,
      ];
      // The old layout showed one row here in the test font (4x fewer).
      expect(visible.length, greaterThanOrEqualTo(4), reason: '$visible');
    });

    testWidgets('one scroll view: no nested vertical scrolling', (
      tester,
    ) async {
      await pump(tester);

      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      expect(vertical, findsOneWidget);
    });

    testWidgets('a long album scrolls to its last track without clipping', (
      tester,
    ) async {
      await pump(
        tester,
        repo: repository(count: 40),
        padding: const EdgeInsets.only(bottom: 96),
      );

      final last = find.byKey(const ValueKey<String>('album-studio-track-s40'));
      await tester.scrollUntilVisible(
        last,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('album-studio-track-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.byKey(const ValueKey<String>('album-studio-track-list')),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      // Fully on screen and clear of a 96px bottom inset.
      final rect = tester.getRect(last);
      expect(rect.bottom, lessThanOrEqualTo(800 - 96));
      expect(tester.takeException(), isNull);
    });
  });

  group('album tools', () {
    testWidgets('expand and collapse, announcing their state', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      final toggle = tool('tools-toggle');
      expect(
        tester.getSemantics(toggle),
        matchesSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          label:
              'Album tools\nDetails, MusicBrainz, Cover Art Archive and '
              'artwork',
        ),
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      for (final key in [
        'edit-details',
        'search-musicbrainz',
        'search-cover-art',
        'change-artwork',
        'clear-artwork',
      ]) {
        expect(tool(key), findsOneWidget, reason: key);
      }

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tool('edit-details'), findsNothing);
      semantics.dispose();
    });

    testWidgets('artwork and details actions still run', (tester) async {
      var details = 0;
      var change = 0;
      var clear = 0;
      await pump(
        tester,
        onEditDetails: () async => details++,
        onChangeArtwork: () async => change++,
        onClearArtwork: () async => clear++,
      );

      await tester.tap(tool('tools-toggle'));
      await tester.pumpAndSettle();
      await tester.tap(tool('edit-details'));
      await tester.pumpAndSettle();
      await tester.tap(tool('change-artwork'));
      await tester.pumpAndSettle();
      await tester.tap(tool('clear-artwork'));
      await tester.pumpAndSettle();

      expect((details, change, clear), (1, 1, 1));
      // MusicBrainz needs its services; without them it is shown, disabled.
      expect(
        tester.widget<ListTile>(tool('search-musicbrainz')).enabled,
        isFalse,
      );
    });
  });

  group('tracks', () {
    testWidgets('dragging the handle reorders through the existing service', (
      tester,
    ) async {
      final (_, ordering) = await pump(tester);

      final handle = find.byKey(const ValueKey<String>('album-studio-drag-s1'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 140));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(ordering.reorderCallCount, 1);
      expect(ordering.lastOrderedSongIds!.first, isNot('s1'));
      expect(ordering.lastOrderedSongIds, contains('s1'));
    });

    testWidgets('tapping a track opens its placement editor', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Song s3'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('album-studio-placement-dialog-s3')),
        findsOneWidget,
      );
    });

    testWidgets('rows show placement, duration and multi-disc numbers', (
      tester,
    ) async {
      await pump(
        tester,
        repo: repository(
          tracks: [track('a', 1), track('b', 10), track('c', 1, disc: 2)],
        ),
      );

      expect(find.text('1-10'), findsOneWidget);
      expect(find.text('Disc 2 • Track 1'), findsOneWidget);
      expect(find.text(' • 3:00'), findsNWidgets(3));
    });

    testWidgets('choosing another edition swaps the editable tracks', (
      tester,
    ) async {
      await pump(tester, repo: repository(count: 3, deluxe: true));

      expect(find.text('Song bonus'), findsNothing);
      await tester.tap(
        find.descendant(
          of: tool('edition-selector'),
          matching: find.text('Deluxe'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song bonus'), findsOneWidget);
    });

    // J3's ordering service now exists, so the control is offered (its
    // behaviour is covered in album_studio_editions_test.dart).
    testWidgets('"Sort by disc & track" sits with the track order', (
      tester,
    ) async {
      await pump(tester);

      final sort = find.byKey(
        const ValueKey<String>('album-studio-sort-disc-track'),
      );
      expect(sort, findsOneWidget);
      expect(tester.widget<OutlinedButton>(sort).onPressed, isNotNull);
    });
  });

  group('small screens and themes', () {
    // Regression (J4 QA): at 320dp and 2x text the number column and
    // buttons left titles so little width that words broke apart.
    testWidgets('at 2x text the title gets the row; placement stays visible', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 2000),
        textScale: 2,
        repo: repository(tracks: [track('a', 1), track('b', 10, disc: 2)]),
      );
      final list = find
          .descendant(
            of: find.byKey(const ValueKey<String>('album-studio-track-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      final title = find.text('Song b');
      await tester.scrollUntilVisible(title, 300, scrollable: list);

      expect(
        find.byKey(const ValueKey<String>('album-studio-edit-placement-b')),
        findsNothing,
      );
      final row = find.byKey(const ValueKey<String>('album-studio-track-b'));
      expect(
        tester.getSize(title).width,
        greaterThan(tester.getSize(row).width * 0.55),
      );
      // The placement is still spelled out.
      expect(
        find.descendant(of: row, matching: find.text('Disc 2 • Track 10')),
        findsOneWidget,
      );

      // Tapping the row still edits the placement.
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('album-studio-placement-dialog-b')),
        findsOneWidget,
      );
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text, tools open', (
        tester,
      ) async {
        await pump(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 6000),
          textScale: 2,
          repo: repository(count: 6, deluxe: true),
        );
        await tester.tap(tool('tools-toggle'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(tool('edit-details'), findsOneWidget);
      });
    }
  });
}
