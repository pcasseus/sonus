import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/track_selection_controller.dart';
import 'package:sonus_next/features/library/presentation/widgets/track_selection_bar.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('TrackSelectionController', () {
    test('keeps selection mode on until exit, even when cleared', () {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);

      selection.start('song_a');
      selection.toggle('song_b');
      expect(selection.isActive, isTrue);
      expect(selection.count, 2);

      selection.toggle('song_a');
      expect(selection.isSelected('song_a'), isFalse);

      selection.clear();
      expect(selection.isActive, isTrue);
      expect(selection.count, 0);

      selection.exit();
      expect(selection.isActive, isFalse);
    });

    test('returns selected songs in list order, each once', () {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);
      final a = _track('song_a');
      final b = _track('song_b');
      final c = _track('song_c');

      selection
        ..start('song_c')
        ..toggle('song_a');

      expect(selection.selectedIn([a, b, c, a]).map((track) => track.songId), [
        'song_a',
        'song_c',
      ]);
      expect(selection.allSelectedIn([a, c]), isTrue);
      expect(selection.allSelectedIn([a, b, c]), isFalse);
    });
  });

  group('TrackSelectionScope', () {
    final tracks = [
      _track('song_a'),
      _track('song_gone', isAvailable: false),
      _track('song_b'),
    ];

    testWidgets('shows the bar only in selection mode, with a live count', (
      tester,
    ) async {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _Harness(selection: selection, tracks: tracks, engine: _Engine()),
      );
      expect(find.byKey(const ValueKey('track-selection-bar')), findsNothing);

      selection.start('song_a');
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('track-selection-all')));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('track-selection-clear')));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('Add to queue'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('Escape and Back leave selection mode without popping', (
      tester,
    ) async {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _Harness(selection: selection, tracks: tracks, engine: _Engine()),
      );

      selection.start('song_a');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(selection.isActive, isFalse);

      selection.start('song_b');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(selection.isActive, isFalse);
      expect(find.byKey(const ValueKey('selection-list')), findsOneWidget);
    });

    testWidgets('adds to the queue in list order and reports skipped songs', (
      tester,
    ) async {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);
      final engine = _Engine();

      await tester.pumpWidget(
        _Harness(selection: selection, tracks: tracks, engine: engine),
      );

      selection
        ..start('song_b')
        ..toggle('song_gone')
        ..toggle('song_a');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('track-selection-queue')));
      await tester.pump();

      expect(engine.appended.map((track) => track.songId), [
        'song_a',
        'song_b',
      ]);
      expect(
        find.text(
          'Added 2 songs to the queue. 1 unavailable song was skipped.',
        ),
        findsOneWidget,
      );
      expect(selection.isActive, isFalse);
    });

    testWidgets('fits 320dp at twice the text size', (tester) async {
      final selection = TrackSelectionController();
      addTearDown(selection.dispose);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: _Harness(
            selection: selection,
            tracks: tracks,
            engine: _Engine(),
          ),
        ),
      );
      selection.start('song_a');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('track-selection-close'))),
        const Size(48, 48),
      );
    });
  });

  test('queue message without skipped songs', () {
    expect(queueMessage(added: 1, total: 1), 'Added 1 song to the queue.');
    expect(
      queueMessage(added: 0, total: 2),
      'No songs were added to the queue. 2 unavailable songs were skipped.',
    );
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.selection,
    required this.tracks,
    required this.engine,
  });

  final TrackSelectionController selection;
  final List<LibraryTrack> tracks;
  final PlaybackEngine engine;

  @override
  Widget build(BuildContext context) {
    return Provider<PlaybackCoordinator>.value(
      value: PlaybackCoordinator(engine: engine),
      child: MaterialApp(
        home: Scaffold(
          body: TrackSelectionScope(
            controller: selection,
            visibleTracks: tracks,
            child: ListView(
              key: const ValueKey('selection-list'),
              children: [for (final track in tracks) Text(track.title)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Engine implements PlaybackEngine {
  final List<PlaybackTrack> appended = [];

  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    appended.add(track);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Not used by this test: ${invocation.memberName}');
  }
}

LibraryTrack _track(String songId, {bool isAvailable = true}) {
  return LibraryTrack(
    songId: songId,
    title: 'Title $songId',
    artistId: 'artist_selection',
    artistName: 'Marlow Vale',
    albumId: 'album_selection',
    albumTitle: 'Harbor Lights',
    albumEditionId: 'edition_selection',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 10, 1),
    filePath: isAvailable ? 'C:/Music/$songId.mp3' : null,
    isAvailable: isAvailable,
  );
}
