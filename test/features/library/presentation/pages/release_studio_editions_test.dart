import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/edition_track_numbering.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/data/services/edition_follow_up_dismissals.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/library/presentation/pages/release_studio_page.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

import 'album_profile_page_test.dart' as base;

// Album Studio edition management, wired to AlbumEditionManagementService.
void main() {
  LibraryTrack track(String id, int number, {String? edition}) =>
      base.createTrack(
        songId: id,
        title: 'Song $id',
        albumEditionId: edition ?? 'edition-standard',
        albumEditionTitle: edition == 'edition-deluxe' ? 'Deluxe' : 'Standard',
        albumEditionType: edition == 'edition-deluxe'
            ? AlbumEditionType.deluxe
            : AlbumEditionType.standard,
        trackNumber: number,
      );

  base.FakeEditionAwareLibraryQueryRepository repository() =>
      base.FakeEditionAwareLibraryQueryRepository(
        album: base.createAlbum(
          title: 'Studio Album',
          primaryEditionId: 'edition-standard',
          primaryEditionTitle: 'Standard',
        ),
        // Every song of the album, for "Choose songs".
        tracks: [track('s1', 1), track('s2', 2), track('bonus', 3)],
        editions: [
          base.createLibraryEdition(
            editionId: 'edition-standard',
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
          ),
          base.createLibraryEdition(
            editionId: 'edition-deluxe',
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
          ),
        ],
        editionTracks: {
          'edition-standard': [track('s1', 1), track('s2', 2)],
          'edition-deluxe': [
            track('s1', 1, edition: 'edition-deluxe'),
            track('bonus', 2, edition: 'edition-deluxe'),
          ],
        },
      );

  Future<(AlbumProfileController, _FakeEditions, _SortingService)> pump(
    WidgetTester tester, {
    _FakeEditions? editions,
    double textScale = 1,
    Size size = const Size(411, 1000),
    base.FakeEditionAwareLibraryQueryRepository? library,
    _MemoryDismissals? dismissals,
    ReleaseStudioSection section = ReleaseStudioSection.editions,
    AlbumProfileEditingService? editing,
    _SortingService? ordering,
    LibraryOrganizationService? organization,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = library ?? repository();
    final orderingService = ordering ?? _SortingService();
    final service = editions ?? _FakeEditions();
    final controller = AlbumProfileController(
      repository: repo,
      albumId: 'album-1',
      albumEditionTrackOrderingService: orderingService,
      albumProfileEditingService: editing,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ReleaseStudioPage(
          controller: controller,
          userId: 'user-1',
          editionManagement: service,
          library: repo,
          editionFollowUpDismissals: dismissals ?? _MemoryDismissals(),
          initialSection: section,
          organization: organization,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, service, orderingService);
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  const tracklist = ReleaseStudioSection.tracklist;

  testWidgets('shows the selected edition, its type and primary status', (
    tester,
  ) async {
    final (controller, _, _) = await pump(tester);

    expect(key('album-studio-editions'), findsOneWidget);
    expect(key('album-studio-edition-primary'), findsOneWidget);
    // The primary edition can't be made primary again.
    expect(key('album-studio-make-primary'), findsNothing);

    await controller.selectEdition('edition-deluxe');
    await tester.pumpAndSettle();

    expect(key('album-studio-edition-primary'), findsNothing);
    expect(key('album-studio-make-primary'), findsOneWidget);
  });

  testWidgets('SN-50 A-Q2C: Shared Details shows Leaked next to Live', (
    tester,
  ) async {
    final library = repository();
    await pump(
      tester,
      library: library,
      section: ReleaseStudioSection.details,
      organization: LibraryOrganizationService(
        library: library,
        collaborators: _NoCollaborators(),
        organization: _NoOrganization(),
      ),
    );
    await tester.scrollUntilVisible(
      key('release-studio-leaked'),
      200,
      scrollable: find
          .descendant(
            of: key('release-studio-scroll'),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(
      tester.getTopLeft(key('release-studio-leaked')).dy,
      greaterThan(tester.getTopLeft(key('release-studio-live')).dy),
    );
    expect(
      find.text(
        'Mark the whole release as leaked. Song leak labels are set per song.',
      ),
      findsOneWidget,
    );
  });

  group('SN-50 A5: deleting an edition', () {
    /// Standard lists [standard]; Deluxe lists [deluxe].
    base.FakeEditionAwareLibraryQueryRepository listing({
      required List<String> standard,
      List<String>? deluxe,
    }) => base.FakeEditionAwareLibraryQueryRepository(
      album: base.createAlbum(
        title: 'Harbor Lights',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      ),
      tracks: [
        for (final (i, id) in {...standard, ...?deluxe}.indexed)
          track(id, i + 1),
      ],
      editions: [
        base.createLibraryEdition(
          editionId: 'edition-standard',
          title: 'Standard',
          type: AlbumEditionType.standard,
          isPrimary: true,
        ),
        if (deluxe != null)
          base.createLibraryEdition(
            editionId: 'edition-deluxe',
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
          ),
      ],
      editionTracks: {
        'edition-standard': [
          for (final (i, id) in standard.indexed) track(id, i + 1),
        ],
        if (deluxe != null)
          'edition-deluxe': [
            for (final (i, id) in deluxe.indexed)
              track(id, i + 1, edition: 'edition-deluxe'),
          ],
      },
    );

    testWidgets('the only edition is never deleted (A-Q24)', (tester) async {
      final (_, service, _) = await pump(
        tester,
        library: listing(standard: ['s1']),
      );

      await tester.tap(key('album-studio-delete-edition'));
      await tester.pumpAndSettle();

      expect(find.textContaining('keeps at least one edition'), findsOne);
      expect(key('album-studio-confirm-delete-edition'), findsNothing);
      expect(service.calls, isEmpty);
    });

    testWidgets('songs only on the edition block it, with their count '
        '(A-Q15, A-Q25)', (tester) async {
      final (controller, service, _) = await pump(
        tester,
        library: listing(standard: ['s1'], deluxe: ['s1', 'b1', 'b2']),
      );
      await controller.selectEdition('edition-deluxe');
      await tester.pumpAndSettle();

      await tester.tap(key('album-studio-delete-edition'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '2 songs are only on this edition. Add them to another edition '
          'first, then delete this one.',
        ),
        findsOne,
      );
      expect(key('album-studio-confirm-delete-edition'), findsNothing);
      expect(service.calls, isEmpty);
    });

    testWidgets('an edition whose songs are all elsewhere goes after a '
        'confirm that counts them', (tester) async {
      final (controller, service, _) = await pump(
        tester,
        library: listing(standard: ['s1', 's2'], deluxe: ['s1', 's2']),
      );
      await controller.selectEdition('edition-deluxe');
      await tester.pumpAndSettle();

      await tester.tap(key('album-studio-delete-edition'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Its 2 songs are also on other editions and stay there.',
        ),
        findsOne,
      );
      await tester.tap(key('album-studio-confirm-delete-edition'));
      await tester.pumpAndSettle();

      expect(service.calls, ['delete edition-deluxe primary=null user-1']);
    });

    testWidgets('the primary edition goes only with a chosen replacement '
        '(A-Q23)', (tester) async {
      final (_, service, _) = await pump(
        tester,
        library: listing(standard: ['s1'], deluxe: ['s1', 'b1']),
      );

      await tester.tap(key('album-studio-delete-edition'));
      await tester.pumpAndSettle();
      expect(key('album-studio-replacement-primary'), findsOne);
      expect(find.textContaining('This is the primary edition.'), findsOne);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);

      await tester.tap(key('album-studio-delete-edition'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-confirm-delete-edition'));
      await tester.pumpAndSettle();

      expect(service.calls, [
        'delete edition-standard primary=edition-deluxe user-1',
      ]);
    });
  });

  testWidgets('edition actions and song membership never share a section', (
    tester,
  ) async {
    await pump(tester);
    expect(key('album-studio-new-edition'), findsOneWidget);
    expect(key('album-studio-choose-songs'), findsNothing);

    final tracklist = key('release-studio-section-tracklist');
    await tester.ensureVisible(tracklist);
    await tester.pumpAndSettle();
    await tester.tap(tracklist);
    await tester.pumpAndSettle();
    expect(key('album-studio-choose-songs'), findsOneWidget);
    for (final action in ['new-edition', 'edit-edition']) {
      expect(
        find.descendant(
          of: key('album-studio-edition-songs'),
          matching: key('album-studio-$action'),
        ),
        findsNothing,
        reason: action,
      );
    }
    expect(
      find.descendant(
        of: key('album-studio-editions'),
        matching: key('album-studio-choose-songs'),
      ),
      findsNothing,
    );
  });

  testWidgets('creates an edition from the dialog', (tester) async {
    final (_, service, _) = await pump(tester);

    await tester.tap(key('album-studio-new-edition'));
    await tester.pumpAndSettle();
    await tester.enterText(key('album-studio-edition-name-field'), 'Live');
    await tester.tap(key('album-studio-save-edition'));
    await tester.pumpAndSettle();

    // SN-45: a new edition starts with the Standard songs by default.
    expect(service.calls, [
      'create album-1 Live deluxe user-1 from edition-standard',
    ]);
  });

  group('SN-45 edition inheritance and follow-ups', () {
    LibraryTrack dated(String id, String edition, DateTime added) =>
        LibraryTrack(
          songId: id,
          title: 'Song $id',
          artistId: 'artist-1',
          artistName: 'Test Artist',
          albumId: 'album-1',
          albumTitle: 'Studio Album',
          albumEditionId: edition,
          albumEditionTitle: edition,
          albumEditionType: AlbumEditionType.standard,
          trackNumber: 1,
          durationSeconds: 180,
          isSingle: false,
          featuredArtists: const [],
          dateAdded: added,
          isAvailable: true,
          filePath: '/music/$id.mp3',
        );

    LibraryAlbumEdition edition(
      String id,
      String title,
      AlbumEditionType type,
      DateTime created, {
      bool primary = false,
    }) => LibraryAlbumEdition(
      editionId: id,
      albumId: 'album-1',
      title: title,
      type: type,
      isPrimary: primary,
      dateAdded: created,
    );

    final day1 = DateTime.utc(2026, 1, 1);
    final day2 = DateTime.utc(2026, 1, 2);
    final day9 = DateTime.utc(2026, 1, 9);

    /// Deluxe (made on day 2) lists every Standard song. "late" joined
    /// Standard on day 9; "spare" is on the album but on no edition shown.
    base.FakeEditionAwareLibraryQueryRepository builtOn({
      bool lateOnStandard = false,
    }) => base.FakeEditionAwareLibraryQueryRepository(
      album: base.createAlbum(
        title: 'Studio Album',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      ),
      tracks: [
        dated('s1', 'edition-standard', day1),
        dated('s2', 'edition-standard', day1),
        dated('late', 'edition-standard', day9),
        dated('spare', 'edition-standard', day1),
      ],
      editions: [
        edition(
          'edition-standard',
          'Standard',
          AlbumEditionType.standard,
          day1,
          primary: true,
        ),
        edition('edition-deluxe', 'Deluxe', AlbumEditionType.deluxe, day2),
      ],
      editionTracks: {
        'edition-standard': [
          dated('s1', 'edition-standard', day1),
          dated('s2', 'edition-standard', day1),
          if (lateOnStandard) dated('late', 'edition-standard', day9),
        ],
        'edition-deluxe': [
          dated('s1', 'edition-deluxe', day1),
          dated('s2', 'edition-deluxe', day1),
        ],
      },
    );

    testWidgets('the new edition dialog previews the inherited songs', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();

      expect(key('album-studio-edition-source-field'), findsOneWidget);
      expect(key('album-studio-inherited-songs'), findsOneWidget);
      expect(find.text('1. Song s1'), findsOneWidget);
      expect(find.text('2. Song s2'), findsOneWidget);
      expect(find.textContaining('Includes 2 songs'), findsOneWidget);
    });

    testWidgets('starting empty is an explicit choice', (tester) async {
      final (_, service, _) = await pump(tester);

      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();
      await tester.enterText(key('album-studio-edition-name-field'), 'Bonus');
      await tester.tap(key('album-studio-edition-source-field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No songs (start empty)').last);
      await tester.pumpAndSettle();

      expect(key('album-studio-inherited-none'), findsOneWidget);

      await tester.tap(key('album-studio-save-edition'));
      await tester.pumpAndSettle();

      expect(service.calls, ['create album-1 Bonus deluxe user-1 from -']);
    });

    testWidgets('adding to Standard asks before touching Deluxe', (
      tester,
    ) async {
      final service = _FakeEditions();
      final dismissals = _MemoryDismissals();
      await pump(
        tester,
        editions: service,
        library: builtOn(),
        dismissals: dismissals,
        section: tracklist,
      );

      await tester.tap(key('album-studio-choose-songs'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-choose-song-spare'));
      await tester.tap(key('album-studio-save-songs'));
      await tester.pumpAndSettle();

      expect(key('album-studio-follow-up-dialog'), findsOneWidget);
      expect(find.text('Also add to Deluxe?'), findsOneWidget);
      expect(service.calls, ['assign edition-standard spare']);

      // The safe answer keeps Deluxe as it is and remembers it.
      await tester.tap(key('album-studio-follow-up-keep'));
      await tester.pumpAndSettle();

      expect(service.calls, ['assign edition-standard spare']);
      expect(dismissals.values['edition-deluxe'], {'spare'});
    });

    testWidgets('choosing to add puts the song on Deluxe too', (tester) async {
      final service = _FakeEditions();
      await pump(
        tester,
        editions: service,
        library: builtOn(),
        section: tracklist,
      );

      await tester.tap(key('album-studio-choose-songs'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-choose-song-spare'));
      await tester.tap(key('album-studio-save-songs'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-follow-up-add'));
      await tester.pumpAndSettle();

      expect(service.calls, [
        'assign edition-standard spare',
        'assign edition-deluxe spare',
      ]);
    });

    testWidgets('a curated Deluxe is never offered new songs', (tester) async {
      final service = _FakeEditions();
      // The default library's Deluxe lacks s2: it was curated.
      await pump(tester, editions: service, section: tracklist);

      await tester.tap(key('album-studio-choose-songs'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-choose-song-bonus'));
      await tester.tap(key('album-studio-save-songs'));
      await tester.pumpAndSettle();

      expect(key('album-studio-follow-up-dialog'), findsNothing);
      expect(service.calls, ['assign edition-standard bonus']);
    });

    testWidgets('a song imported to Standard later shows a quiet notice', (
      tester,
    ) async {
      final service = _FakeEditions();
      final dismissals = _MemoryDismissals();
      await pump(
        tester,
        editions: service,
        library: builtOn(lateOnStandard: true),
        dismissals: dismissals,
        section: tracklist,
      );

      final notice = key('album-studio-follow-up-notice-edition-deluxe');
      expect(notice, findsOneWidget);
      expect(
        find.text('1 song added to Standard is not on Deluxe.'),
        findsOneWidget,
      );
      // Nothing changed by itself.
      expect(service.calls, isEmpty);

      await tester.tap(key('album-studio-follow-up-review-edition-deluxe'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-follow-up-keep'));
      await tester.pumpAndSettle();

      expect(service.calls, isEmpty);
      expect(dismissals.values['edition-deluxe'], {'late'});
      expect(notice, findsNothing);
    });
  });

  testWidgets('make primary asks first, then calls the service', (
    tester,
  ) async {
    final (controller, service, _) = await pump(tester);
    await controller.selectEdition('edition-deluxe');
    await tester.pumpAndSettle();

    await tester.tap(key('album-studio-make-primary'));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty, reason: 'nothing before confirming');

    await tester.tap(key('album-studio-confirm-primary'));
    await tester.pumpAndSettle();

    expect(service.calls, ['primary edition-deluxe user-1']);
  });

  testWidgets('choose songs adds and removes listings, never songs', (
    tester,
  ) async {
    final service = _FakeEditions();
    await pump(tester, editions: service, section: tracklist);

    await tester.tap(key('album-studio-choose-songs'));
    await tester.pumpAndSettle();
    expect(key('album-studio-choose-songs-dialog'), findsOneWidget);

    await tester.tap(key('album-studio-choose-song-bonus')); // add
    await tester.tap(key('album-studio-choose-song-s2')); // remove
    await tester.tap(key('album-studio-save-songs'));
    await tester.pumpAndSettle();

    expect(service.calls, [
      'assign edition-standard bonus',
      'remove edition-standard s2 user-1',
    ]);
  });

  testWidgets('a song only on this edition is kept and explained', (
    tester,
  ) async {
    final service = _FakeEditions(
      refuseRemoval: AlbumEditionRefusal.lastEditionOfSong,
    );
    await pump(tester, editions: service, section: tracklist);

    await tester.tap(key('album-studio-choose-songs'));
    await tester.pumpAndSettle();
    await tester.tap(key('album-studio-choose-song-s2'));
    await tester.tap(key('album-studio-save-songs'));
    await tester.pumpAndSettle();

    expect(
      find.text('One song is only on this edition, so it was kept.'),
      findsOneWidget,
    );
  });

  testWidgets('a refused rename is explained', (tester) async {
    final service = _FakeEditions(
      refuseUpdate: AlbumEditionRefusal.duplicateTitle,
    );
    await pump(tester, editions: service);

    await tester.tap(key('album-studio-edit-edition'));
    await tester.pumpAndSettle();
    await tester.enterText(key('album-studio-edition-name-field'), 'Deluxe');
    await tester.tap(key('album-studio-save-edition'));
    await tester.pumpAndSettle();

    expect(
      find.text('This album already has an edition with that name.'),
      findsOneWidget,
    );
  });

  testWidgets('sort by disc and track uses the ordering service', (
    tester,
  ) async {
    final (_, _, ordering) = await pump(tester, section: tracklist);

    await tester.ensureVisible(key('album-studio-sort-disc-track'));
    await tester.tap(key('album-studio-sort-disc-track'));
    await tester.pumpAndSettle();

    expect(ordering.sortedEditionIds, ['edition-standard']);
    expect(find.text('Sorted by disc and track number.'), findsOneWidget);
  });

  group('SN-50 Session A', () {
    /// Deluxe is primary and dated; Standard has no date or cover of its
    /// own (made-up release).
    base.FakeEditionAwareLibraryQueryRepository deluxePrimary() =>
        base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(
            title: 'Harbor Glass',
            primaryEditionId: 'edition-deluxe',
            primaryEditionTitle: 'Harbor Glass (Deluxe)',
            primaryEditionType: AlbumEditionType.deluxe,
            releaseDate: DateTime.utc(2025, 3, 14),
          ),
          tracks: [track('s1', 1), track('bonus', 2)],
          editions: [
            base.createLibraryEdition(
              editionId: 'edition-standard',
              title: 'Harbor Glass',
              type: AlbumEditionType.standard,
            ),
            base.createLibraryEdition(
              editionId: 'edition-deluxe',
              title: 'Harbor Glass (Deluxe)',
              type: AlbumEditionType.deluxe,
              isPrimary: true,
              releaseDate: DateTime.utc(2025, 3, 14),
              artworkPath: '/covers/harbor-glass-deluxe.jpg',
            ),
          ],
          editionTracks: {
            'edition-standard': [track('s1', 1)],
            'edition-deluxe': [
              track('s1', 1, edition: 'edition-deluxe'),
              track('bonus', 2, edition: 'edition-deluxe'),
            ],
          },
        );

    testWidgets('a new edition starts from the primary edition (A-Q5A)', (
      tester,
    ) async {
      final (_, service, _) = await pump(tester, library: deluxePrimary());

      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-save-edition'));
      await tester.pumpAndSettle();

      // Before SN-50 the Standard-typed edition was preferred.
      expect(service.calls, [
        'create album-1 Harbor Glass (Deluxe) deluxe user-1 '
            'from edition-deluxe',
      ]);
    });

    testWidgets('the suggested name follows the type until edited (A-Q5C)', (
      tester,
    ) async {
      await pump(tester, library: deluxePrimary());

      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();

      String name() => tester
          .widget<TextField>(key('album-studio-edition-name-field'))
          .controller!
          .text;
      expect(name(), 'Harbor Glass (Deluxe)');

      await tester.tap(key('album-studio-edition-type-field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anniversary').last);
      await tester.pumpAndSettle();
      expect(name(), 'Harbor Glass (Anniversary)');

      await tester.enterText(key('album-studio-edition-name-field'), 'Tour');
      await tester.tap(key('album-studio-edition-type-field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remaster').last);
      await tester.pumpAndSettle();
      expect(name(), 'Tour');
    });

    testWidgets('hand-set numbers are renumbered only after asking (A-Q7A)', (
      tester,
    ) async {
      final service = _FakeEditions(manualNumbersKept: 2);
      await pump(tester, editions: service, section: tracklist);

      Future<void> removeS2() async {
        await tester.tap(key('album-studio-choose-songs'));
        await tester.pumpAndSettle();
        await tester.tap(key('album-studio-choose-song-s2'));
        await tester.tap(key('album-studio-save-songs'));
        await tester.pumpAndSettle();
      }

      await removeS2();
      expect(
        find.text('Renumber tracks you numbered yourself?'),
        findsOneWidget,
      );
      expect(service.calls, ['remove edition-standard s2 user-1']);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, ['remove edition-standard s2 user-1']);

      service.calls.clear();
      await removeS2();
      await tester.tap(key('album-studio-confirm-renumber'));
      await tester.pumpAndSettle();
      expect(service.calls, [
        'remove edition-standard s2 user-1',
        'renumber edition-standard overwrite=true',
      ]);
    });

    testWidgets('no question when no hand-set number is affected', (
      tester,
    ) async {
      final service = _FakeEditions();
      await pump(tester, editions: service, section: tracklist);

      await tester.tap(key('album-studio-choose-songs'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-choose-song-s2'));
      await tester.tap(key('album-studio-save-songs'));
      await tester.pumpAndSettle();

      expect(key('album-studio-confirm-renumber'), findsNothing);
      expect(service.calls, ['remove edition-standard s2 user-1']);
    });

    testWidgets('a non-primary edition has its own date, "Not set" (A-Q6C)', (
      tester,
    ) async {
      final editing = _DateRecorder();
      final (controller, _, _) = await pump(
        tester,
        library: deluxePrimary(),
        editing: editing,
        section: ReleaseStudioSection.details,
      );

      expect(
        find.text('Release date of Harbor Glass (Deluxe)'),
        findsOneWidget,
      );
      expect(find.text('March 14, 2025'), findsOneWidget);

      await controller.selectEdition('edition-standard');
      await tester.pumpAndSettle();

      // Standard never borrows the primary edition's date.
      expect(find.text('Release date of Harbor Glass'), findsOneWidget);
      expect(find.text('March 14, 2025'), findsNothing);

      await tester.ensureVisible(key('release-studio-date'));
      await tester.tap(key('release-studio-date'));
      await tester.pumpAndSettle();
      await tester.enterText(key('release-studio-date-field'), '2024-11');
      await tester.tap(key('release-studio-save-date'));
      await tester.pumpAndSettle();

      expect(editing.dates, [
        (
          'edition-standard',
          DateTime.utc(2024, 11),
          ReleaseDatePrecision.month,
        ),
      ]);
      expect(editing.updateCallCount, 0, reason: 'release details untouched');
    });

    testWidgets('an edition without a cover says it uses the primary one', (
      tester,
    ) async {
      final (controller, _, _) = await pump(
        tester,
        library: deluxePrimary(),
        section: ReleaseStudioSection.artwork,
      );
      await controller.selectEdition('edition-standard');
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Harbor Glass has no cover yet. Using the primary edition's cover.",
        ),
        findsOneWidget,
      );
    });
  });

  group('SN-50 shared release details', () {
    /// Deluxe is primary; Standard is listed second (made-up release).
    base.FakeEditionAwareLibraryQueryRepository twoEditions({
      String? standardGenre,
      String? deluxeGenre,
    }) => base.FakeEditionAwareLibraryQueryRepository(
      album: base.createAlbum(
        title: 'Paper Lanterns',
        primaryEditionId: 'edition-deluxe',
        primaryEditionTitle: 'Paper Lanterns (Deluxe)',
        primaryEditionType: AlbumEditionType.deluxe,
        genre: deluxeGenre,
      ),
      tracks: [track('s1', 1), track('bonus', 2)],
      editions: [
        base.createLibraryEdition(
          editionId: 'edition-deluxe',
          title: 'Paper Lanterns (Deluxe)',
          type: AlbumEditionType.deluxe,
          isPrimary: true,
          genre: deluxeGenre,
        ),
        base.createLibraryEdition(
          editionId: 'edition-standard',
          title: 'Paper Lanterns',
          type: AlbumEditionType.standard,
          genre: standardGenre,
        ),
      ],
      editionTracks: {
        'edition-standard': [track('s1', 1)],
        'edition-deluxe': [
          track('s1', 1, edition: 'edition-deluxe'),
          track('bonus', 2, edition: 'edition-deluxe'),
        ],
      },
    );

    Future<void> rename(WidgetTester tester, String name) async {
      await tester.ensureVisible(key('release-studio-name'));
      await tester.tap(key('release-studio-name'));
      await tester.pumpAndSettle();
      await tester.enterText(key('release-studio-name-field'), name);
      await tester.tap(key('release-studio-save-name'));
      await tester.pumpAndSettle();
    }

    testWidgets('the name renames the selected edition, never the base '
        'title (A-Q4)', (tester) async {
      final editing = _DateRecorder();
      final (controller, service, _) = await pump(
        tester,
        library: twoEditions(),
        editing: editing,
        section: ReleaseStudioSection.details,
      );

      expect(find.text('Name of Paper Lanterns (Deluxe)'), findsOneWidget);
      await rename(tester, 'Paper Lanterns (Night Deluxe)');
      expect(service.calls, [
        'update edition-deluxe Paper Lanterns (Night Deluxe) null',
      ]);

      await controller.selectEdition('edition-standard');
      await tester.pumpAndSettle();
      await rename(tester, 'Paper Lanterns (Day)');
      expect(
        service.calls.last,
        'update edition-standard Paper Lanterns (Day) null',
      );
      expect(editing.updateCallCount, 0, reason: 'base title untouched');
    });

    testWidgets('a blank name is refused', (tester) async {
      final (_, service, _) = await pump(
        tester,
        library: twoEditions(),
        editing: _DateRecorder(),
        section: ReleaseStudioSection.details,
      );

      await tester.ensureVisible(key('release-studio-name'));
      await tester.tap(key('release-studio-name'));
      await tester.pumpAndSettle();
      await tester.enterText(key('release-studio-name-field'), '   ');
      await tester.tap(key('release-studio-save-name'));
      await tester.pump();

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('editions with different genres are pointed out (A-Q6F)', (
      tester,
    ) async {
      await pump(
        tester,
        library: twoEditions(deluxeGenre: 'Dream Pop', standardGenre: 'Folk'),
        section: ReleaseStudioSection.details,
      );

      expect(key('release-studio-genre-review'), findsOneWidget);
      expect(
        find.text(
          'Editions have different genres: Dream Pop, Folk. Pick one to use '
          'for the release.',
        ),
        findsOneWidget,
      );
      // Shown by text and an icon, not by color alone.
      expect(find.byIcon(Icons.rule_rounded), findsOneWidget);
    });

    testWidgets('the genre review and edition name fit 320dp at 2x text', (
      tester,
    ) async {
      await pump(
        tester,
        library: twoEditions(deluxeGenre: 'Dream Pop', standardGenre: 'Folk'),
        editing: _DateRecorder(),
        section: ReleaseStudioSection.details,
        textScale: 2,
        size: const Size(320, 2400),
      );

      expect(tester.takeException(), isNull);
      expect(key('release-studio-genre-review'), findsOneWidget);
      expect(key('release-studio-name'), findsOneWidget);
    });

    testWidgets('matching or missing genres need no review', (tester) async {
      await pump(
        tester,
        library: twoEditions(deluxeGenre: 'Folk', standardGenre: ' folk '),
        section: ReleaseStudioSection.details,
      );

      expect(key('release-studio-genre-review'), findsNothing);
    });
  });

  group('SN-50 a Standard added to a Deluxe-led release (A-Q5F)', () {
    base.FakeEditionAwareLibraryQueryRepository deluxeOnly() =>
        base.FakeEditionAwareLibraryQueryRepository(
          album: base.createAlbum(
            title: 'Salt Roads',
            primaryEditionId: 'edition-deluxe',
            primaryEditionTitle: 'Salt Roads (Deluxe)',
            primaryEditionType: AlbumEditionType.deluxe,
          ),
          tracks: [track('s1', 1)],
          editions: [
            base.createLibraryEdition(
              editionId: 'edition-deluxe',
              title: 'Salt Roads (Deluxe)',
              type: AlbumEditionType.deluxe,
              isPrimary: true,
            ),
          ],
          editionTracks: {
            'edition-deluxe': [track('s1', 1, edition: 'edition-deluxe')],
          },
        );

    Future<void> createStandard(WidgetTester tester) async {
      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-edition-type-field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard').last);
      await tester.pumpAndSettle();
      await tester.enterText(key('album-studio-edition-name-field'), 'Salt');
      await tester.tap(key('album-studio-save-edition'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks, and keeps Deluxe primary unless told otherwise', (
      tester,
    ) async {
      final (_, service, _) = await pump(tester, library: deluxeOnly());

      await createStandard(tester);
      expect(find.text('Make the Standard edition primary?'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(service.calls, [
        'create album-1 Salt standard user-1 from edition-deluxe',
      ]);
    });

    testWidgets('makes the Standard primary when the user agrees', (
      tester,
    ) async {
      final (_, service, _) = await pump(tester, library: deluxeOnly());

      await createStandard(tester);
      await tester.tap(key('album-studio-confirm-standard-primary'));
      await tester.pumpAndSettle();

      expect(service.calls, hasLength(2));
      expect(service.calls.last, startsWith('primary '));
      expect(service.calls.last, endsWith(' user-1'));
    });

    testWidgets('no question when the primary is not a Deluxe', (tester) async {
      await pump(tester);

      await tester.tap(key('album-studio-new-edition'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-edition-type-field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard').last);
      await tester.pumpAndSettle();
      await tester.enterText(key('album-studio-edition-name-field'), 'Again');
      await tester.tap(key('album-studio-save-edition'));
      await tester.pumpAndSettle();

      expect(find.text('Make the Standard edition primary?'), findsNothing);
    });
  });

  group('SN-50 placement keeps hand-set numbers unless asked (A-Q7A)', () {
    Future<void> moveToDisc2(WidgetTester tester) async {
      await tester.tap(key('album-studio-edit-placement-s1'));
      await tester.pumpAndSettle();
      await tester.tap(key('album-studio-show-disc-number'));
      await tester.pumpAndSettle();
      await tester.enterText(key('album-studio-disc-number-field'), '2');
      await tester.tap(key('album-studio-save-placement'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before renumbering, and only then renumbers', (
      tester,
    ) async {
      final ordering = _SortingService()..manualNumbersKept = 1;
      final (_, service, _) = await pump(
        tester,
        section: tracklist,
        ordering: ordering,
      );

      await moveToDisc2(tester);
      expect(
        find.text('Renumber tracks you numbered yourself?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);

      await moveToDisc2(tester);
      await tester.tap(key('album-studio-confirm-renumber'));
      await tester.pumpAndSettle();
      expect(service.calls, ['renumber edition-standard overwrite=true']);
    });

    testWidgets('no question when no hand-set number was kept', (tester) async {
      final (_, service, _) = await pump(tester, section: tracklist);

      await moveToDisc2(tester);

      expect(key('album-studio-confirm-renumber'), findsNothing);
      expect(service.calls, isEmpty);
    });
  });

  testWidgets('one disc shows plain numbers, even when it is disc 2 (A-Q8A)', (
    tester,
  ) async {
    LibraryTrack onDisc2(String id, int number) => base.createTrack(
      songId: id,
      title: 'Song $id',
      albumEditionId: 'edition-standard',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: number,
      discNumber: 2,
    );
    final library = base.FakeEditionAwareLibraryQueryRepository(
      album: base.createAlbum(
        title: 'Glass Harbor',
        primaryEditionId: 'edition-standard',
        primaryEditionTitle: 'Standard',
      ),
      tracks: [onDisc2('a', 1), onDisc2('b', 2)],
      editions: [
        base.createLibraryEdition(
          editionId: 'edition-standard',
          title: 'Standard',
          type: AlbumEditionType.standard,
          isPrimary: true,
        ),
      ],
      editionTracks: {
        'edition-standard': [onDisc2('a', 1), onDisc2('b', 2)],
      },
    );

    await pump(tester, library: library, section: tracklist);

    expect(tester.widget<Text>(key('album-studio-placement-a')).data, '1');
    // Disc controls stay one tap away in the placement dialog.
    await tester.tap(key('album-studio-edit-placement-a'));
    await tester.pumpAndSettle();
    expect(key('album-studio-disc-number-field'), findsOneWidget);
  });

  testWidgets('editions fit 320dp at 2x text', (tester) async {
    await pump(tester, textScale: 2, size: const Size(320, 1400));

    expect(tester.takeException(), isNull);
    expect(key('album-studio-new-edition'), findsOneWidget);
  });
}

class _FakeEditions implements AlbumEditionManagementService {
  _FakeEditions({
    this.refuseRemoval,
    this.refuseUpdate,
    this.manualNumbersKept = 0,
  });

  final AlbumEditionRefusal? refuseRemoval;
  final AlbumEditionRefusal? refuseUpdate;

  /// Hand-set numbers a track-list change reports leaving alone.
  final int manualNumbersKept;
  final List<String> calls = [];

  @override
  SyncMutationRunner get mutationRunner => throw UnimplementedError();

  @override
  Future<AlbumEdition> createEdition({
    required String albumId,
    required String title,
    required AlbumEditionType type,
    String? includeSongsFrom,
    DateTime? releaseDate,
    String? userId,
    DateTime? now,
  }) async {
    calls.add(
      'create $albumId $title ${type.name} $userId '
      'from ${includeSongsFrom ?? '-'}',
    );
    return EntityFactory.createAlbumEdition(
      albumId: albumId,
      title: title,
      type: type,
    );
  }

  @override
  Future<AlbumEdition> updateEdition({
    required String editionId,
    String? title,
    AlbumEditionType? type,
    String? userId,
    DateTime? now,
  }) async {
    final refusal = refuseUpdate;
    if (refusal != null) throw AlbumEditionManagementException(refusal);
    calls.add('update $editionId $title ${type?.name}');
    return EntityFactory.createAlbumEdition(
      albumId: 'album-1',
      title: title ?? 'x',
    );
  }

  @override
  Future<void> setPrimary({
    required String editionId,
    String? userId,
    DateTime? now,
  }) async {
    calls.add('primary $editionId $userId');
  }

  @override
  Future<int> assignTracks({
    required String editionId,
    required List<String> songIds,
    bool renumber = true,
    String? userId,
    DateTime? now,
  }) async {
    calls.add('assign $editionId ${songIds.join(',')}');
    return songIds.length;
  }

  @override
  Future<EditionRenumberResult> removeTrack({
    required String editionId,
    required String songId,
    String? userId,
    DateTime? now,
  }) async {
    final refusal = refuseRemoval;
    if (refusal != null) throw AlbumEditionManagementException(refusal);
    calls.add('remove $editionId $songId $userId');
    return EditionRenumberResult.none;
  }

  /// Records the same calls as one assignment plus one removal per song,
  /// as the real batch applies them.
  @override
  Future<AlbumEditionTrackListResult> updateTrackList({
    required String editionId,
    List<String> add = const [],
    List<String> remove = const [],
    String? userId,
    DateTime? now,
  }) async {
    if (add.isNotEmpty) calls.add('assign $editionId ${add.join(',')}');
    var kept = 0;
    for (final songId in remove) {
      if (refuseRemoval == AlbumEditionRefusal.lastEditionOfSong) {
        kept++;
      } else {
        calls.add('remove $editionId $songId $userId');
      }
    }
    return AlbumEditionTrackListResult(
      added: add.length,
      removed: remove.length - kept,
      keptAsLastListing: kept,
      renumbering: EditionRenumberResult(
        renumbered: 0,
        manualNumbersKept: manualNumbersKept,
      ),
    );
  }

  @override
  Future<EditionRenumberResult> renumberEdition({
    required String editionId,
    bool overwriteManual = false,
    String? userId,
    DateTime? now,
  }) async {
    calls.add('renumber $editionId overwrite=$overwriteManual');
    return const EditionRenumberResult(renumbered: 1, manualNumbersKept: 0);
  }

  @override
  Future<void> deleteEdition({
    required String editionId,
    String? replacementPrimaryId,
    String? userId,
    DateTime? now,
  }) async {
    calls.add('delete $editionId primary=$replacementPrimaryId $userId');
  }
}

class _NoCollaborators implements ProjectCollaboratorQueryRepository {
  @override
  Future<List<ProjectCollaborator>> getProjectCollaborators({
    String? albumId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoOrganization implements LibraryOrganizationRepository {
  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async =>
      const [];

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async => const [];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async =>
      const [];

  @override
  Future<List<AlbumLeakedClassification>> getLeakedClassifications() async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DateRecorder extends base.FakeAlbumProfileEditingService {
  final List<(String, DateTime?, ReleaseDatePrecision?)> dates = [];

  @override
  Future<AlbumEdition> updateEditionReleaseDate({
    required String? userId,
    required String editionId,
    required DateTime? releaseDate,
    ReleaseDatePrecision? releaseDatePrecision,
    DateTime? now,
  }) async {
    dates.add((editionId, releaseDate, releaseDatePrecision));
    return EntityFactory.createAlbumEdition(albumId: 'album-1', title: 'x');
  }
}

class _SortingService extends base.FakeAlbumEditionTrackOrderingService {
  final List<String> sortedEditionIds = [];

  /// Hand-set numbers a placement change reports leaving alone.
  int manualNumbersKept = 0;

  @override
  Future<AlbumEditionTrackPlacementResult> updateTrackPlacement({
    required String? userId,
    required String albumEditionId,
    required String songId,
    required int discNumber,
    required int trackNumber,
    DateTime? now,
  }) async {
    final result = await super.updateTrackPlacement(
      userId: userId,
      albumEditionId: albumEditionId,
      songId: songId,
      discNumber: discNumber,
      trackNumber: trackNumber,
      now: now,
    );
    return AlbumEditionTrackPlacementResult(
      membership: result.membership,
      changed: result.changed,
      compatibilitySongChanged: result.compatibilitySongChanged,
      manualNumbersKept: manualNumbersKept,
    );
  }

  @override
  Future<AlbumEditionReorderResult> sortByDiscAndTrack({
    required String albumEditionId,
    String? userId,
    DateTime? now,
  }) async {
    sortedEditionIds.add(albumEditionId);
    return const AlbumEditionReorderResult(memberships: [], changed: true);
  }
}

class _MemoryDismissals implements EditionFollowUpDismissals {
  final Map<String, Set<String>> values = {};

  @override
  Future<Set<String>> dismissed(String targetEditionId) async => {
    ...?values[targetEditionId],
  };

  @override
  Future<void> dismiss(String targetEditionId, Iterable<String> songIds) async {
    values.putIfAbsent(targetEditionId, () => {}).addAll(songIds);
  }
}
