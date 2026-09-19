import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_profile_edit_dialog.dart';

void main() {
  LibraryTrack buildTrack() {
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
      featuredArtists: const ['Guest One', 'Guest Two'],
      dateAdded: DateTime(2026),
      isAvailable: true,
    );
  }

  LibraryArtist buildExistingArtist() {
    return LibraryArtist(
      artistId: 'artist-1',
      name: 'Artist',
      albumCount: 1,
      songCount: 1,
      dateAdded: DateTime(2026),
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    LibraryTrack track, {
    List<LibraryArtist> artists = const [],
    TrackArtistCreationCallback? onCreateArtist,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  showDialog<TrackProfileEditDraft>(
                    context: context,
                    builder: (_) => TrackProfileEditDialog(
                      track: track,
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
  }

  Future<void> ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
    expect(finder, findsOneWidget);

    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();

    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('prepopulates existing track metadata', (tester) async {
    await pumpDialog(tester, buildTrack());

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
    final featuredField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
    );
    final singleToggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('track-single-toggle')),
    );

    expect(titleField.controller!.text, 'Original Song');
    expect(numberField.controller!.text, '3');
    expect(discNumberField.controller!.text, '2');
    expect(featuredField.controller!.text, 'Guest One, Guest Two');
    expect(singleToggle.value, isFalse);
  });

  testWidgets('validates blank title', (tester) async {
    await pumpDialog(tester, buildTrack());

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

  testWidgets('returns normalized edited metadata', (tester) async {
    TrackProfileEditDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showDialog<TrackProfileEditDraft>(
                    context: context,
                    builder: (_) => TrackProfileEditDialog(track: buildTrack()),
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
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
      ' Guest A, , Guest B ',
    );

    final singleToggleFinder = find.byKey(
      const ValueKey<String>('track-single-toggle'),
    );
    await ensureVisibleAndTap(tester, singleToggleFinder);

    final saveButton = find.byKey(
      const ValueKey<String>('track-edit-save-button'),
    );
    await ensureVisibleAndTap(tester, saveButton);

    expect(result, isNotNull);
    expect(result!.title, 'Edited Song');
    expect(result!.trackNumber, 7);
    expect(result!.discNumber, 4);
    expect(result!.featuredArtists, ['Guest A', 'Guest B']);
    expect(result!.isSingle, isTrue);
  });

  testWidgets('artist creation is hidden without callback', (tester) async {
    await pumpDialog(tester, buildTrack());

    expect(
      find.byKey(const ValueKey<String>('track-add-primary-artist-button')),
      findsNothing,
    );
  });

  testWidgets(
    'created artist is selected and existing draft state is preserved',
    (tester) async {
      TrackProfileEditDraft? result;
      String? requestedName;

      final existingArtist = buildExistingArtist();

      final createdArtist = LibraryArtist(
        artistId: 'artist-created',
        name: 'Victoria Justice',
        albumCount: 0,
        songCount: 0,
        dateAdded: DateTime(2026),
      );

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
                        track: buildTrack(),
                        artists: [existingArtist],
                        onCreateArtist: (name) async {
                          requestedName = name;
                          return createdArtist;
                        },
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
      await tester.enterText(
        find.byKey(const ValueKey<String>('track-featured-artists-field')),
        'Ariana Grande',
      );

      final singleToggleFinder = find.byKey(
        const ValueKey<String>('track-single-toggle'),
      );
      await ensureVisibleAndTap(tester, singleToggleFinder);

      final addArtistButton = find.byKey(
        const ValueKey<String>('track-add-primary-artist-button'),
      );
      await ensureVisibleAndTap(tester, addArtistButton);

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
      final featuredField = tester.widget<TextFormField>(
        find.byKey(const ValueKey<String>('track-featured-artists-field')),
      );
      final singleToggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey<String>('track-single-toggle')),
      );

      expect(titleField.controller!.text, 'Draft Title');
      expect(numberField.controller!.text, '5');
      expect(discField.controller!.text, '3');
      expect(featuredField.controller!.text, 'Ariana Grande');
      expect(singleToggle.value, isTrue);

      final saveButton = find.byKey(
        const ValueKey<String>('track-edit-save-button'),
      );
      await ensureVisibleAndTap(tester, saveButton);

      expect(result, isNotNull);
      expect(result!.artistId, 'artist-created');
      expect(result!.title, 'Draft Title');
      expect(result!.trackNumber, 5);
      expect(result!.discNumber, 3);
      expect(result!.featuredArtists, ['Ariana Grande']);
      expect(result!.isSingle, isTrue);
    },
  );

  testWidgets('blank new artist name is rejected locally', (tester) async {
    var createCallCount = 0;

    await pumpDialog(
      tester,
      buildTrack(),
      artists: [buildExistingArtist()],
      onCreateArtist: (name) async {
        createCallCount++;
        return null;
      },
    );

    final addArtistButton = find.byKey(
      const ValueKey<String>('track-add-primary-artist-button'),
    );
    await ensureVisibleAndTap(tester, addArtistButton);

    expect(find.text('Add new artist'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('track-new-artist-save-button')),
    );
    await tester.pump();

    expect(find.text('Artist name cannot be blank.'), findsOneWidget);
    expect(createCallCount, 0);
    expect(find.text('Add new artist'), findsOneWidget);
  });
}
