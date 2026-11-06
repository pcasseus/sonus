// UI redesign E1: saving a credit in Track Studio's credit editor stores the
// credits at once. The Studio's other edits stay unsaved drafts, its main
// Save cannot write a stale copy back, and Back cannot undo saved credits.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/track_profile_edit_draft.dart';
import 'package:sonus_next/features/library/presentation/pages/track_studio_page.dart';

LibraryTrack _track() => LibraryTrack(
  songId: 'song-1',
  title: 'Stored Title',
  artistId: 'artist-1',
  artistName: 'Primary Artist',
  albumId: 'album-1',
  albumTitle: 'Album',
  albumEditionId: 'edition-1',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime(2026),
  isAvailable: true,
);

LibraryArtist _artist(String id, String name) => LibraryArtist(
  artistId: id,
  name: name,
  albumCount: 1,
  songCount: 1,
  dateAdded: DateTime(2026),
);

const _existing = TrackProfileCreditDraft(
  creditedName: 'Old Guest',
  role: SongArtistCreditRole.guest,
);

class _Saver {
  final calls = <List<TrackProfileCreditDraft>>[];

  /// What the save returns; by default the credits as given.
  List<TrackProfileCreditDraft> Function(List<TrackProfileCreditDraft>) stored =
      (credits) => credits;
  Object? error;
  Completer<void>? gate;

  Future<List<TrackProfileCreditDraft>?> call(
    List<TrackProfileCreditDraft> credits,
  ) async {
    calls.add(List.of(credits));
    await gate?.future;
    if (error != null) throw error!;
    return stored(credits);
  }
}

void main() {
  late _Saver saver;
  TrackProfileEditDraft? popped;
  var closed = false;

  setUp(() {
    saver = _Saver();
    popped = null;
    closed = false;
  });

  Future<void> open(
    WidgetTester tester, {
    bool withSaver = true,
    List<TrackProfileCreditDraft> initial = const [_existing],
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                popped = await Navigator.of(context)
                    .push<TrackProfileEditDraft>(
                      MaterialPageRoute(
                        builder: (_) => TrackStudioPage(
                          track: _track(),
                          artists: [
                            _artist('artist-1', 'Primary Artist'),
                            _artist('artist-2', 'Other Artist'),
                          ],
                          initialAdditionalCredits: initial,
                          onSaveCredits: withSaver ? saver.call : null,
                        ),
                      ),
                    );
                closed = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  Future<void> addCredit(WidgetTester tester, String name) async {
    await tester.ensureVisible(key('track-add-credit-button'));
    await tester.tap(key('track-add-credit-button'));
    await tester.pumpAndSettle();
    await tester.enterText(key('track-credit-name-field'), name);
    await tester.tap(key('track-credit-save-button'));
    await tester.pumpAndSettle();
  }

  Future<void> pressBack(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
  }

  testWidgets('saving a credit stores the credits at once', (tester) async {
    await open(tester);

    await addCredit(tester, 'New Feature');

    expect(saver.calls, hasLength(1));
    expect(saver.calls.single.map((credit) => credit.creditedName), [
      'Old Guest',
      'New Feature',
    ]);
    expect(key('track-studio-credits-saved-message'), findsOneWidget);
  });

  testWidgets('removing a credit is saved at once too', (tester) async {
    await open(tester);

    await tester.ensureVisible(key('track-remove-credit-0'));
    await tester.tap(key('track-remove-credit-0'));
    await tester.pumpAndSettle();

    expect(saver.calls.single, isEmpty);
    expect(find.text('Old Guest'), findsNothing);
  });

  testWidgets('Back after saving credits leaves without asking: nothing is '
      'left unsaved, and the saved credits stay saved', (tester) async {
    await open(tester);
    await addCredit(tester, 'New Feature');

    await pressBack(tester);

    expect(closed, isTrue);
    expect(popped, isNull, reason: 'no draft: nothing else saved');
    expect(saver.calls, hasLength(1), reason: 'nothing undone');
  });

  testWidgets('other unsaved edits are kept as drafts; Back asks, and '
      'Discard keeps the saved credits', (tester) async {
    await open(tester);
    await tester.enterText(key('track-title-field'), 'Draft Title');
    await addCredit(tester, 'New Feature');

    // The title edit survived the credit save.
    expect(find.text('Draft Title'), findsOneWidget);

    await pressBack(tester);
    expect(key('track-studio-discard-dialog'), findsOneWidget);
    expect(
      find.textContaining('Credits you already saved stay saved.'),
      findsOneWidget,
    );

    await tester.tap(key('track-studio-keep-editing'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('Draft Title'), findsOneWidget);

    await pressBack(tester);
    await tester.tap(key('track-studio-discard'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(popped, isNull);
    expect(saver.calls, hasLength(1));
  });

  testWidgets('the main Save sends the credits as stored, never the older '
      'editor copy', (tester) async {
    // The store normalises: it keeps only the new credit.
    saver.stored = (credits) => [credits.last];
    await open(tester);
    await tester.enterText(key('track-title-field'), 'Draft Title');
    await addCredit(tester, 'New Feature');

    // The editor now shows what was stored.
    expect(find.text('Old Guest'), findsNothing);

    await tester.tap(key('track-studio-save-button'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.title, 'Draft Title');
    expect(popped!.additionalCredits.map((credit) => credit.creditedName), [
      'New Feature',
    ]);
  });

  testWidgets('an unsaved primary artist change holds the credits for Save, '
      'with an explanation', (tester) async {
    await open(tester);

    await tester.ensureVisible(key('track-primary-artist-field'));
    await tester.tap(key('track-primary-artist-field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Artist').last);
    await tester.pumpAndSettle();

    await addCredit(tester, 'New Feature');

    expect(saver.calls, isEmpty, reason: 'not saved against an unsaved artist');
    expect(key('track-studio-credits-wait-message'), findsOneWidget);
    expect(find.text('New Feature'), findsOneWidget, reason: 'kept as draft');

    await tester.tap(key('track-studio-save-button'));
    await tester.pumpAndSettle();
    expect(popped!.artistId, 'artist-2');
    expect(popped!.additionalCredits.map((credit) => credit.creditedName), [
      'Old Guest',
      'New Feature',
    ]);
  });

  testWidgets('a failed save restores the stored credits and says so', (
    tester,
  ) async {
    saver.error = StateError('disk full');
    await open(tester);

    await addCredit(tester, 'New Feature');

    expect(saver.calls, hasLength(1));
    expect(find.text('New Feature'), findsNothing);
    expect(find.text('Old Guest'), findsOneWidget);
    expect(key('track-studio-credits-failed-message'), findsOneWidget);
    expect(find.text('Could not save the credits.'), findsOneWidget);
  });

  testWidgets('a primary artist changed elsewhere is reported', (tester) async {
    saver.error = const TrackCreditPrimaryArtistChangedException(
      songId: 'song-1',
      expectedPrimaryArtistId: 'artist-1',
      storedPrimaryArtistId: 'artist-9',
    );
    await open(tester);

    await addCredit(tester, 'New Feature');

    expect(
      find.text(
        "This song's primary artist changed, so the credits were not saved.",
      ),
      findsOneWidget,
    );
    expect(find.text('New Feature'), findsNothing);
  });

  testWidgets('a credit repeating the primary artist is refused by the '
      'editor and never saved', (tester) async {
    await open(tester);

    await tester.ensureVisible(key('track-add-credit-button'));
    await tester.tap(key('track-add-credit-button'));
    await tester.pumpAndSettle();
    await tester.enterText(key('track-credit-name-field'), 'Primary Artist');
    await tester.tap(key('track-credit-save-button'));
    await tester.pumpAndSettle();

    expect(
      find.text('Primary Artist is already the primary artist.'),
      findsOneWidget,
    );
    expect(saver.calls, isEmpty);
  });

  testWidgets('a list that would repeat the primary artist is not saved '
      '(a second guard behind the editor)', (tester) async {
    // An older duplicate the editor never checked.
    await open(
      tester,
      initial: const [
        _existing,
        TrackProfileCreditDraft(
          creditedName: 'Primary Artist',
          role: SongArtistCreditRole.guest,
        ),
      ],
    );

    await tester.ensureVisible(key('track-remove-credit-0'));
    await tester.tap(key('track-remove-credit-0'));
    await tester.pumpAndSettle();

    expect(saver.calls, isEmpty);
    expect(
      find.textContaining('so the credits were not saved'),
      findsOneWidget,
    );
    expect(find.text('Old Guest'), findsOneWidget, reason: 'unchanged');
  });

  testWidgets('the credit list waits while a save is in flight', (
    tester,
  ) async {
    saver.gate = Completer<void>();
    await open(tester);

    await addCredit(tester, 'New Feature');
    expect(
      tester
          .widgetList<AbsorbPointer>(
            find.ancestor(
              of: key('track-add-credit-button'),
              matching: find.byType(AbsorbPointer),
            ),
          )
          .any((widget) => widget.absorbing),
      isTrue,
    );

    saver.gate!.complete();
    await tester.pumpAndSettle();
    expect(saver.calls, hasLength(1));
  });

  testWidgets('without a credit saver, credits stay drafts as before', (
    tester,
  ) async {
    await open(tester, withSaver: false);

    await addCredit(tester, 'New Feature');
    expect(key('track-studio-credits-saved-message'), findsNothing);

    await tester.tap(key('track-studio-save-button'));
    await tester.pumpAndSettle();
    expect(popped!.additionalCredits.map((credit) => credit.creditedName), [
      'Old Guest',
      'New Feature',
    ]);
  });

  // Typing does not rebuild the page by itself; Back must still ask.
  testWidgets('Back after only typing in a field asks first', (tester) async {
    await open(tester);

    await tester.enterText(key('track-title-field'), 'Typed Title');
    await tester.pump();
    await pressBack(tester);

    expect(key('track-studio-discard-dialog'), findsOneWidget);
    expect(closed, isFalse);
    expect(saver.calls, isEmpty);
  });

  testWidgets('typing a field back to its stored value lets Back leave', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(key('track-title-field'), 'Typed Title');
    await tester.pump();
    await tester.enterText(key('track-title-field'), 'Stored Title');
    await tester.pump();
    await pressBack(tester);

    expect(closed, isTrue);
    expect(key('track-studio-discard-dialog'), findsNothing);
  });

  testWidgets('Back with no edits at all leaves at once', (tester) async {
    await open(tester);

    await pressBack(tester);

    expect(closed, isTrue);
    expect(key('track-studio-discard-dialog'), findsNothing);
  });
}
