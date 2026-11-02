import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/release_studio_page.dart';

import 'album_profile_page_test.dart' as base;

// Release Studio layout (SN-45; track list from SN-48J J4).
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
    ReleaseStudioSection section = ReleaseStudioSection.tracklist,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ordering = base.FakeAlbumEditionTrackOrderingService();
    final library = repo ?? repository();
    final controller = AlbumProfileController(
      repository: library,
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
        home: ReleaseStudioPage(
          controller: controller,
          userId: null,
          onChangeArtwork: onChangeArtwork,
          onClearArtwork: onClearArtwork,
          initialSection: section,
          library: library,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, ordering);
  }

  Finder tool(String key) => find.byKey(ValueKey<String>('album-studio-$key'));
  final scroll = find.byKey(const ValueKey<String>('release-studio-scroll'));

  /// Opens a collapsed section (or closes an open one) by its heading.
  Future<void> toggleSection(WidgetTester tester, String name) async {
    final header = find.byKey(ValueKey<String>('release-studio-section-$name'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  group('layout', () {
    // Regression (J4): a fixed tools card above the list left about three
    // track rows visible on a phone. The Tracklist has its own section.
    testWidgets('the tracklist gets the screen', (tester) async {
      await pump(tester);

      expect(tool('change-artwork'), findsNothing);
      final visible = [
        for (var n = 1; n <= 20; n++)
          if (find
              .byKey(ValueKey<String>('album-studio-track-s$n'))
              .hitTestable()
              .evaluate()
              .isNotEmpty)
            n,
      ];
      expect(visible.length, greaterThanOrEqualTo(4), reason: '$visible');
    });

    testWidgets('one scroll view per section: no nested vertical scrolling', (
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
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first,
      );
      await tester.drag(scroll, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // Fully on screen and clear of a 96px bottom inset.
      final rect = tester.getRect(last);
      expect(rect.bottom, lessThanOrEqualTo(800 - 96));
      expect(tester.takeException(), isNull);
    });
  });

  group('shared details above edition sections, each action once', () {
    Finder key(String value) => find.byKey(ValueKey<String>(value));

    testWidgets('Shared details, then the edition\'s sections (A-Q6A)', (
      tester,
    ) async {
      await pump(tester, section: ReleaseStudioSection.details);

      expect(find.text('Edit Release'), findsOneWidget);
      for (final name in [
        'shared',
        'name',
        'artwork',
        'editions',
        'tracklist',
      ]) {
        expect(
          key('release-studio-section-$name'),
          findsOneWidget,
          reason: name,
        );
      }
      // Shared details come first.
      expect(
        tester.getTopLeft(key('release-studio-section-shared')).dy,
        lessThan(tester.getTopLeft(key('release-studio-section-name')).dy),
      );
      for (final row in ['name', 'owner', 'date', 'genre']) {
        expect(key('release-studio-$row'), findsOneWidget, reason: row);
      }
      // Shared values live only in Shared details; the edition's name and
      // date are edited only in its own section (A-Q4).
      for (final row in ['owner', 'genre']) {
        expect(
          find.descendant(
            of: key('release-studio-details'),
            matching: key('release-studio-$row'),
          ),
          findsOneWidget,
          reason: row,
        );
      }
      for (final row in ['name', 'date']) {
        expect(
          find.descendant(
            of: key('release-studio-details'),
            matching: key('release-studio-$row'),
          ),
          findsNothing,
          reason: row,
        );
      }
      // Artwork actions live only under Artwork, which starts closed.
      expect(tool('change-artwork'), findsNothing);

      await toggleSection(tester, 'artwork');
      for (final action in [
        'change-artwork',
        'search-cover-art',
        'clear-artwork',
      ]) {
        expect(
          find.descendant(
            of: key('release-studio-artwork'),
            matching: tool(action),
          ),
          findsOneWidget,
          reason: action,
        );
      }
      expect(
        find.descendant(
          of: key('release-studio-artwork'),
          matching: key('release-studio-name'),
        ),
        findsNothing,
      );

      // Shared details collapse; their values are gone from the screen.
      await toggleSection(tester, 'shared');
      expect(key('release-studio-owner'), findsNothing);
      expect(key('release-studio-name'), findsOneWidget);
    });

    testWidgets('one edition opens straight into its editor, without tabs', (
      tester,
    ) async {
      await pump(tester, section: ReleaseStudioSection.details);

      expect(key('release-studio-edition-tabs'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Release date'), findsOneWidget);
    });

    testWidgets('editions are tabs, primary first and marked Primary (A-Q6B)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (controller, _) = await pump(
        tester,
        section: ReleaseStudioSection.details,
        repo: repository(count: 3, deluxe: true),
      );

      final tabs = key('release-studio-edition-tabs');
      expect(tabs, findsOneWidget);
      final standard = key('release-studio-edition-tab-edition-standard');
      final deluxe = key('release-studio-edition-tab-edition-deluxe');
      expect(
        tester.getTopLeft(standard).dx,
        lessThan(tester.getTopLeft(deluxe).dx),
      );
      expect(
        find.descendant(
          of: standard,
          matching: key('release-studio-edition-tab-primary'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: deluxe,
          matching: key('release-studio-edition-tab-primary'),
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Standard, primary edition')),
        findsOneWidget,
      );
      // Tabs sit between Shared details and the edition's sections.
      expect(
        tester.getTopLeft(tabs).dy,
        lessThan(tester.getTopLeft(key('release-studio-section-name')).dy),
      );

      await tester.tap(deluxe);
      await tester.pumpAndSettle();

      expect(controller.selectedEdition?.editionId, 'edition-deluxe');
      expect(find.text('Name of Deluxe'), findsOneWidget);
      // Shared values stay in Shared details, whichever edition is shown.
      expect(
        find.descendant(
          of: key('release-studio-details'),
          matching: key('release-studio-owner'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('sections open by keyboard and say whether they are open', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, section: ReleaseStudioSection.details);
      final shared = key('release-studio-section-shared');
      final tile = find.descendant(of: shared, matching: find.byType(ListTile));

      expect(
        tester.getSemantics(tile),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );

      for (var presses = 0; presses < 10; presses++) {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null &&
            find
                .descendant(of: tile, matching: find.byWidget(focused.widget))
                .evaluate()
                .isNotEmpty) {
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(key('release-studio-owner'), findsNothing);
      expect(
        tester.getSemantics(tile),
        isSemantics(hasExpandedState: true, isExpanded: false),
      );
      semantics.dispose();
    });

    testWidgets('artwork actions run for the selected edition', (tester) async {
      var change = 0;
      var clear = 0;
      await pump(
        tester,
        section: ReleaseStudioSection.artwork,
        onChangeArtwork: () async => change++,
        onClearArtwork: () async => clear++,
        repo: base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(
            title: 'Studio Album',
            primaryEditionId: 'edition-standard',
          ),
          editions: [
            base.createLibraryEdition(
              editionId: 'edition-standard',
              title: 'Standard',
              type: AlbumEditionType.standard,
              isPrimary: true,
              artworkPath: 'missing/cover.jpg',
            ),
          ],
          editionTracks: {
            'edition-standard': [track('s1', 1)],
          },
        ),
      );

      await tester.tap(tool('change-artwork'));
      await tester.pumpAndSettle();
      await tester.tap(tool('clear-artwork'));
      await tester.pumpAndSettle();

      expect((change, clear), (1, 1));
      // Cover Art Archive needs its services; without them it is disabled.
      expect(
        tester.widget<ListTile>(tool('search-cover-art')).enabled,
        isFalse,
      );
    });

    testWidgets('an edition without its own cover has nothing to remove', (
      tester,
    ) async {
      var clear = 0;
      await pump(
        tester,
        section: ReleaseStudioSection.artwork,
        onClearArtwork: () async => clear++,
      );

      await tester.tap(tool('clear-artwork'));
      await tester.pumpAndSettle();

      expect(clear, 0);
      expect(find.text('Standard has no cover yet'), findsOneWidget);
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

    testWidgets('a Deluxe edition marks the songs only it has as bonus', (
      tester,
    ) async {
      final (controller, _) = await pump(
        tester,
        repo: repository(count: 3, deluxe: true),
      );
      await controller.selectEdition('edition-deluxe');
      await tester.pumpAndSettle();

      final bonus = find.byKey(
        const ValueKey<String>('album-studio-track-bonus'),
      );
      final inherited = find.byKey(
        const ValueKey<String>('album-studio-track-s1'),
      );
      expect(
        find.descendant(of: bonus, matching: find.text(' • Bonus track')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inherited, matching: find.textContaining('Bonus')),
        findsNothing,
      );
    });

    testWidgets('choosing another edition swaps the editable tracks', (
      tester,
    ) async {
      await pump(tester, repo: repository(count: 3, deluxe: true));

      expect(find.text('Song bonus'), findsNothing);
      final deluxe = find.byKey(
        const ValueKey<String>('release-studio-edition-tab-edition-deluxe'),
      );
      await tester.ensureVisible(deluxe);
      await tester.pumpAndSettle();
      await tester.tap(deluxe);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Song bonus'),
        200,
        scrollable: find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first,
      );

      expect(find.text('Song bonus'), findsOneWidget);
    });

    // J3's ordering service now exists, so the control is offered (its
    // behaviour is covered in release_studio_editions_test.dart).
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
          .descendant(of: scroll, matching: find.byType(Scrollable))
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
      testWidgets('${id.label} fits 320dp at 2x text in every section', (
        tester,
      ) async {
        await pump(
          tester,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 6000),
          textScale: 2,
          repo: repository(count: 6, deluxe: true),
          section: ReleaseStudioSection.details,
        );
        // Every section open at once, on each edition's tab.
        for (final name in ['artwork', 'editions', 'tracklist']) {
          await toggleSection(tester, name);
          expect(tester.takeException(), isNull, reason: name);
        }
        for (final edition in ['edition-deluxe', 'edition-standard']) {
          final tab = find.byKey(
            ValueKey<String>('release-studio-edition-tab-$edition'),
          );
          await tester.ensureVisible(tab);
          await tester.pumpAndSettle();
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: edition);
        }
        await tester.scrollUntilVisible(
          find.text('Song s6'),
          400,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
