import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/edition_track_numbering.dart';
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
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = library ?? repository();
    final ordering = _SortingService();
    final service = editions ?? _FakeEditions();
    final controller = AlbumProfileController(
      repository: repo,
      albumId: 'album-1',
      albumEditionTrackOrderingService: ordering,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, service, ordering);
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  const tracklist = ReleaseStudioSection.tracklist;

  testWidgets('shows the selected edition, its type and primary status', (
    tester,
  ) async {
    final (controller, _, _) = await pump(tester);

    expect(key('album-studio-editions'), findsOneWidget);
    expect(key('album-studio-edition-primary'), findsOneWidget);
    // The primary edition can't be made primary again or deleted.
    expect(key('album-studio-make-primary'), findsNothing);
    expect(key('album-studio-delete-edition'), findsNothing);

    await controller.selectEdition('edition-deluxe');
    await tester.pumpAndSettle();

    expect(key('album-studio-edition-primary'), findsNothing);
    expect(key('album-studio-make-primary'), findsOneWidget);
    // Not empty, so it can't be deleted.
    expect(key('album-studio-delete-edition'), findsNothing);
  });

  testWidgets('edition actions and song membership never share a section', (
    tester,
  ) async {
    await pump(tester);
    expect(key('album-studio-new-edition'), findsOneWidget);
    expect(key('album-studio-choose-songs'), findsNothing);

    await tester.tap(key('release-studio-tab-tracklist'));
    await tester.pumpAndSettle();
    expect(key('album-studio-choose-songs'), findsOneWidget);
    expect(key('album-studio-new-edition'), findsNothing);
    expect(key('album-studio-edit-edition'), findsNothing);
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
    String? userId,
  }) async {
    calls.add('delete $editionId');
  }
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
