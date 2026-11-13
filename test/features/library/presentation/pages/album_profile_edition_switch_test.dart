// App Update 1.2, PATCH-01: the Standard/Deluxe selector on the device.
// A tap on Deluxe did not move at first; another tap switched to Deluxe and
// then back. A refresh (from automatic sync or a recorded play) that began
// before the tap finished after it and restored the edition it began with.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/account/presentation/scopes/account_scope.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';

import 'album_profile_page_test.dart'
    show
        FakeEditionAwareLibraryQueryRepository,
        createAlbum,
        createLibraryEdition,
        createTrack;

void main() {
  late _GatedRepository repository;
  late LibraryChangeSignal changes;

  setUp(() {
    repository = _GatedRepository();
    changes = LibraryChangeSignal();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(_app(repository, changes));
    await tester.pumpAndSettle();
    expect(find.text('Standard Song'), findsOneWidget);
  }

  Future<void> tapEdition(WidgetTester tester, String label) async {
    final selector = find.byKey(
      const ValueKey<String>('album-profile-edition-segmented-button'),
    );
    await tester.tap(find.descendant(of: selector, matching: find.text(label)));
  }

  Set<String> selectorSelection(WidgetTester tester) {
    final button = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    return button.selected;
  }

  void expectDeluxeShown() {
    expect(find.text('Standard Song'), findsNothing);
    expect(find.text('Deluxe Song'), findsOneWidget);
    expect(find.text('Bonus Song'), findsOneWidget);
    expect(find.text('3 tracks • 9 min'), findsOneWidget);
    expect(find.text('June 20, 2025'), findsOneWidget);
  }

  void expectStandardShown() {
    expect(find.text('Standard Song'), findsOneWidget);
    expect(find.text('Bonus Song'), findsNothing);
    expect(find.text('1 track • 3 min'), findsOneWidget);
    expect(find.text('May 17, 2024'), findsOneWidget);
  }

  testWidgets('one tap on Deluxe switches once and stays, even when a '
      'refresh that began first finishes after it (the device bug)', (
    tester,
  ) async {
    await pumpPage(tester);

    // Automatic sync records a change; its refresh starts and is slow.
    repository.gateAlbumReads = true;
    changes.notify(LibraryChangeKind.libraryEdited);
    await tester.pump(const Duration(milliseconds: 350));
    expect(repository.heldAlbumReads, 1);
    repository.gateAlbumReads = false;

    await tapEdition(tester, 'Deluxe');
    await tester.pump();
    expect(selectorSelection(tester), {_deluxe}, reason: 'moves at once');
    await tester.pumpAndSettle();
    expectDeluxeShown();

    repository.releaseAlbumReads();
    await tester.pumpAndSettle();

    expect(selectorSelection(tester), {_deluxe});
    expectDeluxeShown();
  });

  testWidgets('disc headings follow the edition: Deluxe spans two discs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<String?> headings() => [
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'album-profile-disc-heading-',
                    ),
              )
              .evaluate())
        (element.widget as Text).data,
    ];
    await pumpPage(tester);
    expect(headings(), isEmpty);

    await tapEdition(tester, 'Deluxe');
    await tester.pumpAndSettle();
    expect(headings(), ['Disc 1', 'Disc 2']);

    await tapEdition(tester, 'Standard');
    await tester.pumpAndSettle();
    expect(headings(), isEmpty);
  });

  testWidgets('rapid alternating taps end on the last edition tapped', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.gateTrackReads = true;

    for (final label in ['Deluxe', 'Standard', 'Deluxe', 'Standard']) {
      await tapEdition(tester, label);
      await tester.pump();
    }
    await tapEdition(tester, 'Deluxe');
    await tester.pump();
    expect(selectorSelection(tester), {_deluxe});

    // The held reads finish newest first: the oldest would win if stale
    // results were not discarded.
    repository.releaseTrackReadsNewestFirst();
    await tester.pumpAndSettle();

    expect(selectorSelection(tester), {_deluxe});
    expectDeluxeShown();
  });

  testWidgets('a second tap on the chosen edition does not switch back', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.gateTrackReads = true;

    await tapEdition(tester, 'Deluxe');
    await tester.pump();
    await tapEdition(tester, 'Deluxe');
    await tester.pump();
    expect(repository.trackReadsAfterLoad, [_deluxe]);

    repository.releaseTrackReadsNewestFirst();
    await tester.pumpAndSettle();
    expectDeluxeShown();

    await tapEdition(tester, 'Deluxe');
    await tester.pumpAndSettle();
    expectDeluxeShown();
    expect(repository.trackReadsAfterLoad, [_deluxe]);
  });

  testWidgets('the edition stays chosen after going to another page and '
      'back, and after listening is recorded meanwhile', (tester) async {
    await pumpPage(tester);
    await tapEdition(tester, 'Deluxe');
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Elsewhere')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Elsewhere'), findsOneWidget);
    changes.notify(LibraryChangeKind.listeningRecorded);
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pumpAndSettle();

    expect(selectorSelection(tester), {_deluxe});
    expectDeluxeShown();

    await tapEdition(tester, 'Standard');
    await tester.pumpAndSettle();
    expect(selectorSelection(tester), {_standard});
    expectStandardShown();
  });

  testWidgets('an edition that cannot be read stays unselected, with a '
      'message', (tester) async {
    await pumpPage(tester);
    repository.failTrackReadsOf = _deluxe;

    await tapEdition(tester, 'Deluxe');
    await tester.pumpAndSettle();

    expect(selectorSelection(tester), {_standard});
    expectStandardShown();
    expect(
      find.text('That edition could not be opened. Try again.'),
      findsOneWidget,
    );
  });
}

const _standard = 'edition-standard';
const _deluxe = 'edition-deluxe';

Widget _app(LibraryQueryRepository repository, LibraryChangeSignal changes) {
  return MultiProvider(
    providers: [Provider<LibraryQueryRepository?>.value(value: repository)],
    child: AccountScope(
      repository: null,
      child: MaterialApp(
        home: AlbumProfilePage(
          albumId: 'album-1',
          initialAlbumTitle: 'Concept Album',
          changes: changes,
        ),
      ),
    ),
  );
}

class _GatedRepository extends FakeEditionAwareLibraryQueryRepository {
  _GatedRepository()
    : super(
        album: _album,
        editions: [
          createLibraryEdition(
            editionId: _standard,
            title: 'Standard',
            type: AlbumEditionType.standard,
            isPrimary: true,
            releaseDate: DateTime(2024, 5, 17),
          ),
          createLibraryEdition(
            editionId: _deluxe,
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
            releaseDate: DateTime(2025, 6, 20),
          ),
        ],
        editionTracks: {
          _standard: [
            createTrack(
              songId: 'song-shared',
              title: 'Standard Song',
              albumEditionId: _standard,
              albumEditionTitle: 'Standard',
              trackNumber: 1,
            ),
          ],
          _deluxe: [
            createTrack(
              songId: 'song-deluxe',
              title: 'Deluxe Song',
              albumEditionId: _deluxe,
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 1,
            ),
            createTrack(
              songId: 'song-shared',
              title: 'Shared Song',
              albumEditionId: _deluxe,
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              trackNumber: 2,
            ),
            createTrack(
              songId: 'song-bonus',
              title: 'Bonus Song',
              albumEditionId: _deluxe,
              albumEditionTitle: 'Deluxe',
              albumEditionType: AlbumEditionType.deluxe,
              discNumber: 2,
              trackNumber: 1,
            ),
          ],
        },
      );

  static final LibraryAlbum _album = createAlbum(
    title: 'Concept Album',
    primaryEditionId: _standard,
    primaryEditionTitle: 'Standard',
    primaryEditionType: AlbumEditionType.standard,
  );

  bool gateAlbumReads = false;
  bool gateTrackReads = false;
  String? failTrackReadsOf;
  bool _loaded = false;
  final List<String> trackReadsAfterLoad = [];
  final List<Completer<void>> _albumGates = [];
  final List<Completer<void>> _trackGates = [];

  int get heldAlbumReads => _albumGates.length;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    if (gateAlbumReads) {
      final gate = Completer<void>();
      _albumGates.add(gate);
      await gate.future;
    }
    return super.getAlbumById(albumId);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) async {
    if (_loaded) trackReadsAfterLoad.add(editionId);
    _loaded = true;
    if (gateTrackReads) {
      final gate = Completer<void>();
      _trackGates.add(gate);
      await gate.future;
    }
    if (editionId == failTrackReadsOf) throw StateError('read failed');
    return super.getTracksByAlbumEditionId(editionId);
  }

  void releaseAlbumReads() {
    for (final gate in _albumGates) {
      gate.complete();
    }
    _albumGates.clear();
  }

  void releaseTrackReadsNewestFirst() {
    gateTrackReads = false;
    for (final gate in _trackGates.reversed) {
      gate.complete();
    }
    _trackGates.clear();
  }
}
