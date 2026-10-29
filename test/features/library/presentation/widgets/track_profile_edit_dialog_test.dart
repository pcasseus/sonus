import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_profile_edit_dialog.dart';

void main() {
  LibraryTrack buildTrack({
    List<String> featuredArtists = const ['Guest One', 'Guest Two'],
  }) {
    return LibraryTrack(
      songId: 'song-1',
      title: 'Original Song',
      artistId: 'artist-1',
      artistName: 'Artist',
      albumId: 'album-1',
      albumTitle: 'Album',
      albumEditionId: 'edition-1',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 3,
      discNumber: 2,
      durationSeconds: 240,
      isSingle: false,
      featuredArtists: featuredArtists,
      dateAdded: DateTime(2026),
      isAvailable: true,
    );
  }

  LibraryArtist buildArtist(String id, String name) {
    return LibraryArtist(
      artistId: id,
      name: name,
      albumCount: 1,
      songCount: 1,
      dateAdded: DateTime(2026),
    );
  }

  LibraryArtist buildExistingArtist() => buildArtist('artist-1', 'Artist');

  /// The credits Import Review opens with for a song without structured
  /// credits: its older featured names.
  List<TrackProfileCreditDraft> legacyCredits(LibraryTrack track) {
    return trackStudioInitialCredits(
      credits: const [],
      legacyFeaturedArtists: track.featuredArtists,
      primaryArtistId: track.artistId,
      primaryArtistName: track.artistName,
    );
  }

  /// Opens the dialog and returns a getter for the draft it closes with.
  Future<TrackProfileEditDraft? Function()> pumpDialog(
    WidgetTester tester, {
    LibraryTrack? track,
    List<TrackProfileCreditDraft>? initialCredits,
    List<LibraryArtist> artists = const [],
    TrackArtistCreationCallback? onCreateArtist,
  }) async {
    TrackProfileEditDraft? result;
    final editedTrack = track ?? buildTrack();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showDialog<TrackProfileEditDraft>(
                    context: context,
                    builder: (_) => TrackProfileEditDialog(
                      track: editedTrack,
                      initialAdditionalCredits:
                          initialCredits ?? legacyCredits(editedTrack),
                      artists: artists,
                      onCreateArtist: onCreateArtist,
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    return () => result;
  }

  Future<void> ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
    expect(finder, findsOneWidget);

    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();

    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) {
    return ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
  }

  /// Adds a credit through the shared credit editor by typing [name]; picks
  /// [pickArtistId] from the search list when given.
  Future<void> addCredit(
    WidgetTester tester,
    String name, {
    String? pickArtistId,
    String? roleLabel,
  }) async {
    await ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-add-credit-button')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-credit-name-field')),
      name,
    );
    await tester.pumpAndSettle();

    if (pickArtistId != null) {
      await tester.tap(
        find.byKey(
          ValueKey<String>('track-credit-artist-option-$pickArtistId'),
        ),
      );
      await tester.pumpAndSettle();
    }

    if (roleLabel != null) {
      await tester.tap(
        find.byKey(const ValueKey<String>('track-credit-role-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(roleLabel).last);
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('track-credit-save-button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prepopulates existing track metadata and credits', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('Edit song details'), findsOneWidget);

    final titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-title-field')),
    );
    final numberField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-number-field')),
    );
    final discNumberField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-disc-number-field')),
    );
    final singleToggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('track-single-toggle')),
    );

    expect(titleField.controller!.text, 'Original Song');
    expect(numberField.controller!.text, '3');
    expect(discNumberField.controller!.text, '2');
    expect(singleToggle.value, isFalse);
    expect(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('track-credit-row-0')),
        matching: find.text('Guest One'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('track-credit-row-1')),
        matching: find.text('Guest Two'),
      ),
      findsOneWidget,
    );
    expect(find.text('Featured'), findsNWidgets(2));
  });

  testWidgets('validates blank title', (tester) async {
    await pumpDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-title-field')),
      '   ',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
    await tester.pump();

    expect(find.text('Song title cannot be blank.'), findsOneWidget);
  });

  testWidgets('returns normalized edited metadata and credits', (tester) async {
    final result = await pumpDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-title-field')),
      '  Edited Song  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-number-field')),
      '7',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-disc-number-field')),
      '4',
    );
    await ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-remove-credit-1')),
    );
    await addCredit(tester, ' Guest B ', roleLabel: 'Guest');
    await ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-single-toggle')),
    );
    await save(tester);

    final draft = result();
    expect(draft, isNotNull);
    expect(draft!.title, 'Edited Song');
    expect(draft.trackNumber, 7);
    expect(draft.discNumber, 4);
    expect(draft.featuredArtists, ['Guest One']);
    expect(
      [
        for (final credit in draft.additionalCredits)
          (credit.creditedName, credit.role, credit.artistId),
      ],
      [
        ('Guest One', SongArtistCreditRole.featured, null),
        ('Guest B', SongArtistCreditRole.guest, null),
      ],
    );
    expect(draft.isSingle, isTrue);
  });

  testWidgets('keeps stored co-primary and guest credits on save', (
    tester,
  ) async {
    final result = await pumpDialog(
      tester,
      track: buildTrack(featuredArtists: const []),
      initialCredits: const [
        TrackProfileCreditDraft(
          creditedName: 'Ada Vale',
          role: SongArtistCreditRole.coPrimary,
          artistId: 'artist-ada',
        ),
        TrackProfileCreditDraft(
          creditedName: 'Ben Moor',
          role: SongArtistCreditRole.guest,
        ),
      ],
    );

    expect(find.text('Co-primary'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);

    await save(tester);

    final credits = result()!.additionalCredits;
    expect(
      [for (final c in credits) (c.creditedName, c.role, c.artistId)],
      [
        ('Ada Vale', SongArtistCreditRole.coPrimary, 'artist-ada'),
        ('Ben Moor', SongArtistCreditRole.guest, null),
      ],
    );
    expect(result()!.featuredArtists, isEmpty);
  });

  testWidgets('artist creation is hidden without callback', (tester) async {
    await pumpDialog(tester);

    expect(
      find.byKey(const ValueKey<String>('track-add-primary-artist-button')),
      findsNothing,
    );
  });

  testWidgets(
    'created artist is selected and existing draft state is preserved',
    (tester) async {
      String? requestedName;

      final createdArtist = LibraryArtist(
        artistId: 'artist-created',
        name: 'Victoria Justice',
        albumCount: 0,
        songCount: 0,
        dateAdded: DateTime(2026),
      );

      final result = await pumpDialog(
        tester,
        track: buildTrack(featuredArtists: const []),
        artists: [buildExistingArtist()],
        onCreateArtist: (name) async {
          requestedName = name;
          return createdArtist;
        },
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('track-title-field')),
        'Draft Title',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('track-number-field')),
        '5',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('track-disc-number-field')),
        '3',
      );
      await addCredit(tester, 'Mira Sol');
      await ensureVisibleAndTap(
        tester,
        find.byKey(const ValueKey<String>('track-single-toggle')),
      );

      await ensureVisibleAndTap(
        tester,
        find.byKey(const ValueKey<String>('track-add-primary-artist-button')),
      );

      expect(find.text('Add new artist'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('track-new-artist-name-field')),
        '  Victoria Justice  ',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('track-new-artist-save-button')),
      );
      await tester.pumpAndSettle();

      expect(requestedName, 'Victoria Justice');
      expect(find.text('Add new artist'), findsNothing);
      expect(find.text('Edit song details'), findsOneWidget);

      final titleField = tester.widget<TextFormField>(
        find.byKey(const ValueKey<String>('track-title-field')),
      );
      final numberField = tester.widget<TextFormField>(
        find.byKey(const ValueKey<String>('track-number-field')),
      );
      final discField = tester.widget<TextFormField>(
        find.byKey(const ValueKey<String>('track-disc-number-field')),
      );
      final singleToggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey<String>('track-single-toggle')),
      );

      expect(titleField.controller!.text, 'Draft Title');
      expect(numberField.controller!.text, '5');
      expect(discField.controller!.text, '3');
      expect(find.text('Mira Sol'), findsOneWidget);
      expect(singleToggle.value, isTrue);

      await save(tester);

      final draft = result();
      expect(draft, isNotNull);
      expect(draft!.artistId, 'artist-created');
      expect(draft.title, 'Draft Title');
      expect(draft.trackNumber, 5);
      expect(draft.discNumber, 3);
      expect(draft.featuredArtists, ['Mira Sol']);
      expect(draft.isSingle, isTrue);
    },
  );

  testWidgets('blank new artist name is rejected locally', (tester) async {
    var createCallCount = 0;

    await pumpDialog(
      tester,
      artists: [buildExistingArtist()],
      onCreateArtist: (name) async {
        createCallCount++;
        return null;
      },
    );

    await ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-add-primary-artist-button')),
    );

    expect(find.text('Add new artist'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('track-new-artist-save-button')),
    );
    await tester.pump();

    expect(find.text('Artist name cannot be blank.'), findsOneWidget);
    expect(createCallCount, 0);
    expect(find.text('Add new artist'), findsOneWidget);
  });

  testWidgets('a credit that becomes the primary artist blocks saving', (
    tester,
  ) async {
    final result = await pumpDialog(
      tester,
      track: buildTrack(featuredArtists: const []),
      artists: [buildExistingArtist(), buildArtist('artist-ada', 'Ada Vale')],
      initialCredits: const [
        TrackProfileCreditDraft(
          creditedName: 'Ada Vale',
          role: SongArtistCreditRole.featured,
          artistId: 'artist-ada',
        ),
      ],
    );

    await ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('track-primary-artist-field')),
    );
    await tester.tap(find.text('Ada Vale').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(result(), isNull);
    expect(
      find.byKey(const ValueKey<String>('track-credit-conflict')),
      findsOneWidget,
    );
    expect(find.text('Edit song details'), findsOneWidget);
  });

  group('names containing commas (SN-50 audit #13, C-Q5)', () {
    testWidgets('saving unchanged keeps a featured name with a comma whole', (
      tester,
    ) async {
      final result = await pumpDialog(
        tester,
        track: buildTrack(
          featuredArtists: const ['Crane, The Lantern', 'Ada Vale'],
        ),
      );

      await save(tester);

      expect(result()!.featuredArtists, ['Crane, The Lantern', 'Ada Vale']);
    });

    testWidgets('a typed name with a comma is one credit and is not linked', (
      tester,
    ) async {
      final result = await pumpDialog(
        tester,
        track: buildTrack(featuredArtists: const []),
        artists: [
          buildExistingArtist(),
          buildArtist('artist-crane', 'Crane, The Lantern'),
        ],
      );

      await addCredit(tester, 'Crane, The Lantern');
      await save(tester);

      final credits = result()!.additionalCredits;
      expect(credits, hasLength(1));
      expect(credits.single.creditedName, 'Crane, The Lantern');
      expect(credits.single.artistId, isNull);
      expect(credits.single.toInput().linkByName, isFalse);
    });

    testWidgets('picking the artist from the list links the credit', (
      tester,
    ) async {
      final result = await pumpDialog(
        tester,
        track: buildTrack(featuredArtists: const []),
        artists: [
          buildExistingArtist(),
          buildArtist('artist-crane', 'Crane, The Lantern'),
        ],
      );

      await addCredit(
        tester,
        'Crane',
        pickArtistId: 'artist-crane',
        roleLabel: 'Co-primary',
      );
      await save(tester);

      final credit = result()!.additionalCredits.single;
      expect(credit.creditedName, 'Crane, The Lantern');
      expect(credit.role, SongArtistCreditRole.coPrimary);
      expect(credit.artistId, 'artist-crane');
    });
  });
}
