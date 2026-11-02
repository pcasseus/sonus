import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_credit_editor_dialog.dart';

LibraryArtist _artist(String id, String name) {
  return LibraryArtist(
    artistId: id,
    name: name,
    albumCount: 0,
    songCount: 0,
    dateAdded: DateTime(2026),
  );
}

final _artists = [
  _artist('artist-ada', 'Ada Vale'),
  _artist('artist-crane', 'Crane, The Lantern'),
  _artist('artist-cranes', 'Cranes'),
];

final _nameField = find.byKey(
  const ValueKey<String>('track-credit-name-field'),
);
final _saveButton = find.byKey(
  const ValueKey<String>('track-credit-save-button'),
);

class _Harness {
  TrackProfileCreditDraft? result;
  bool closed = false;
}

Future<_Harness> _open(
  WidgetTester tester, {
  List<TrackProfileCreditDraft> otherCredits = const [],
  TrackProfileCreditDraft? initialCredit,
}) async {
  final harness = _Harness();

  await tester.pumpWidget(
    MaterialApp(
      theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                harness.result = await showTrackCreditEditor(
                  context: context,
                  artists: _artists,
                  primaryArtistId: 'artist-ada',
                  primaryArtistName: 'Ada Vale',
                  otherCredits: otherCredits,
                  initialCredit: initialCredit,
                );
                harness.closed = true;
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

  return harness;
}

Future<void> _chooseRole(WidgetTester tester, String label) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('track-credit-role-field')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Track Studio credit editor (SN-50 C-Q2/C-Q3/C-Q4)', () {
    testWidgets('searching offers library artists and picking one links it', (
      tester,
    ) async {
      final harness = await _open(tester);

      await tester.enterText(_nameField, 'cran');
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('track-credit-artist-option-artist-crane'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('track-credit-artist-option-artist-cranes'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('track-credit-artist-option-artist-crane'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Linked to the existing artist Crane, The Lantern.'),
        findsOneWidget,
      );

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.creditedName, 'Crane, The Lantern');
      expect(harness.result!.artistId, 'artist-crane');
      expect(harness.result!.role, SongArtistCreditRole.featured);
    });

    testWidgets('the keyboard can pick a suggestion', (tester) async {
      final harness = await _open(tester);

      await tester.enterText(_nameField, 'cranes');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.artistId, 'artist-cranes');
    });

    testWidgets('a typed name matching an artist is never linked unasked', (
      tester,
    ) async {
      final harness = await _open(tester);

      await tester.enterText(_nameField, 'crane, the lantern');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('track-credit-link-status')),
        findsOneWidget,
      );

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.creditedName, 'crane, the lantern');
      expect(harness.result!.artistId, isNull);
    });

    testWidgets('a new free-text name saves unlinked', (tester) async {
      final harness = await _open(tester);

      await tester.enterText(_nameField, '  Wren Hollow ');
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.creditedName, 'Wren Hollow');
      expect(harness.result!.artistId, isNull);
    });

    testWidgets('refuses the primary artist with a message', (tester) async {
      final harness = await _open(tester);

      await tester.enterText(_nameField, 'ADA  vale');
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(find.text('ADA  vale is already the primary artist.'), findsOne);
      expect(harness.closed, isFalse);
    });

    testWidgets('refuses a repeat of another credit with a message', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        otherCredits: const [
          TrackProfileCreditDraft(
            creditedName: 'Wren Hollow',
            role: SongArtistCreditRole.featured,
          ),
        ],
      );

      await tester.enterText(_nameField, 'wren hollow');
      await tester.pumpAndSettle();
      await _chooseRole(tester, 'Guest');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(
        find.text('wren hollow is already credited on this song.'),
        findsOneWidget,
      );
      expect(harness.closed, isFalse);
    });

    testWidgets(
      'a co-primary matching an artist must be picked from the list',
      (tester) async {
        final harness = await _open(tester);

        await tester.enterText(_nameField, 'Cranes');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _chooseRole(tester, 'Co-primary');
        await tester.tap(_saveButton);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Choose Cranes from the list to credit that artist as '
            'co-primary.',
          ),
          findsOneWidget,
        );
        expect(harness.closed, isFalse);
      },
    );

    testWidgets('editing keeps the link until the name changes', (
      tester,
    ) async {
      const linked = TrackProfileCreditDraft(
        creditedName: 'Cranes',
        role: SongArtistCreditRole.featured,
        artistId: 'artist-cranes',
      );

      var harness = await _open(tester, initialCredit: linked);
      await _chooseRole(tester, 'Guest');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.artistId, 'artist-cranes');
      expect(harness.result!.role, SongArtistCreditRole.guest);

      harness = await _open(tester, initialCredit: linked);
      await tester.enterText(_nameField, 'Cranes Again');
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(harness.result!.creditedName, 'Cranes Again');
      expect(harness.result!.artistId, isNull);
    });

    testWidgets('Track Studio refuses to save when a new primary artist is '
        'also credited, instead of dropping the credit', (tester) async {
      TrackProfileEditDraft? draft;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  draft = await Navigator.of(context)
                      .push<TrackProfileEditDraft>(
                        MaterialPageRoute(
                          builder: (_) => TrackStudioPage(
                            track: LibraryTrack(
                              songId: 'song-1',
                              title: 'Paper Boats',
                              artistId: 'artist-ada',
                              artistName: 'Ada Vale',
                              albumId: 'album-1',
                              albumTitle: 'Harbour',
                              albumEditionId: 'edition-1',
                              albumEditionTitle: 'Standard',
                              albumEditionType: AlbumEditionType.standard,
                              trackNumber: 1,
                              durationSeconds: 200,
                              isSingle: false,
                              featuredArtists: const ['Cranes'],
                              dateAdded: DateTime(2026),
                              isAvailable: true,
                            ),
                            artists: _artists,
                            initialAdditionalCredits: const [
                              TrackProfileCreditDraft(
                                creditedName: 'Cranes',
                                role: SongArtistCreditRole.featured,
                                artistId: 'artist-cranes',
                              ),
                            ],
                          ),
                        ),
                      );
                  closed = true;
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-primary-artist-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cranes').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('track-studio-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Cranes is already credited as the primary artist'),
        findsOneWidget,
      );
      expect(closed, isFalse);
      expect(draft, isNull);
      expect(
        find.byKey(const ValueKey<String>('track-studio-page')),
        findsOneWidget,
      );
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _open(tester);
      await tester.enterText(_nameField, 'Cranes');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
