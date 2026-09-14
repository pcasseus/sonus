import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      durationSeconds: 240,
      isSingle: false,
      featuredArtists: const ['Guest One', 'Guest Two'],
      dateAdded: DateTime(2026),
      isAvailable: true,
    );
  }

  Future<void> pumpDialog(WidgetTester tester, LibraryTrack track) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  showDialog<TrackProfileEditDraft>(
                    context: context,
                    builder: (_) => TrackProfileEditDialog(track: track),
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

  testWidgets('prepopulates existing track metadata', (tester) async {
    await pumpDialog(tester, buildTrack());

    expect(find.text('Edit song details'), findsOneWidget);

    final titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-title-field')),
    );
    final numberField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-number-field')),
    );
    final featuredField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
    );
    final singleToggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('track-single-toggle')),
    );

    expect(titleField.controller!.text, 'Original Song');
    expect(numberField.controller!.text, '3');
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
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
      ' Guest A, , Guest B ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('track-single-toggle')));

    await tester.tap(
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, 'Edited Song');
    expect(result!.trackNumber, 7);
    expect(result!.featuredArtists, ['Guest A', 'Guest B']);
    expect(result!.isSingle, isTrue);
  });
}
