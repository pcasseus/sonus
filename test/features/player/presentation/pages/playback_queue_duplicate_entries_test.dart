import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/player/presentation/pages/playback_queue_page.dart';

import '../../data/engines/simulated_just_audio_player.dart';

// SN-50 F2: a song can be queued more than once (multi-select "Add to
// queue" makes it easy). Each copy is its own row, and removing, moving or
// playing one copy acts on that copy only. Fictional values only.
const _a = PlaybackTrack(
  songId: 'song-a',
  title: 'Paper Lanterns',
  artistId: 'artist-1',
  artistName: 'Harbor Lights',
  albumId: 'album-1',
  albumTitle: 'Tidewater',
  filePath: '/music/paper-lanterns.mp3',
  duration: Duration(minutes: 3),
);

const _b = PlaybackTrack(
  songId: 'song-b',
  title: 'Salt Roads',
  artistId: 'artist-1',
  artistName: 'Harbor Lights',
  albumId: 'album-1',
  albumTitle: 'Tidewater',
  filePath: '/music/salt-roads.mp3',
  duration: Duration(minutes: 4),
);

void main() {
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late PlaybackStateController stateController;

  setUp(() {
    engine = JustAudioPlaybackEngine(
      audioPlayer: SimulatedJustAudioPlayer(),
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
    stateController = PlaybackStateController(coordinator: coordinator);
  });

  tearDown(() async {
    stateController.dispose();
    await engine.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> pumpQueue(
    WidgetTester tester,
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(411, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => engine.loadQueue(tracks, startIndex: startIndex),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaybackCoordinator>.value(value: coordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(
            value: stateController,
          ),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: const PlaybackQueuePage(),
        ),
      ),
    );
    await settle(tester);
  }

  List<String> queuedSongIds() => [
    for (final track in engine.currentState.queue.tracks) track.songId,
  ];

  Finder row(String entryId) =>
      find.byKey(ValueKey<String>('queue-track-$entryId'));

  testWidgets('each copy of a song is its own row', (tester) async {
    await pumpQueue(tester, const [_a, _b, _a]);

    expect(tester.takeException(), isNull);
    expect(row('song-a'), findsOneWidget);
    expect(row('song-b'), findsOneWidget);
    expect(row('song-a#2'), findsOneWidget);
    expect(find.text('Paper Lanterns'), findsNWidgets(2));
  });

  testWidgets('a copy added to the queue gets its own row', (tester) async {
    await pumpQueue(tester, const [_a, _b]);

    await tester.runAsync(() => engine.appendTrack(_a));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(queuedSongIds(), ['song-a', 'song-b', 'song-a']);
    expect(row('song-a#2'), findsOneWidget);
  });

  testWidgets('removing one copy keeps the other and the playing song', (
    tester,
  ) async {
    await pumpQueue(tester, const [_a, _b, _a]);

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-remove-song-a#2')),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(queuedSongIds(), ['song-a', 'song-b']);
    expect(engine.currentState.queue.currentIndex, 0);
    expect(row('song-a'), findsOneWidget);
    expect(row('song-a#2'), findsNothing);
  });

  testWidgets('removing the playing copy leaves the later copy queued', (
    tester,
  ) async {
    await pumpQueue(tester, const [_a, _b, _a], startIndex: 2);

    await tester.tap(find.byKey(const ValueKey<String>('queue-remove-song-a')));
    await settle(tester);

    expect(queuedSongIds(), ['song-b', 'song-a']);
    expect(engine.currentState.queue.currentIndex, 1);
    expect(engine.currentState.queue.currentTrack?.songId, 'song-a');
  });

  testWidgets('dragging a copy moves that copy, and the playing copy keeps '
      'playing', (tester) async {
    await pumpQueue(tester, const [_a, _b, _a]);
    final rowHeight = tester.getSize(row('song-b')).height;

    // Move the later copy of A (index 2) above B.
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('queue-drag-song-a#2')),
      ),
    );
    await tester.pump();
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(Offset(0, -rowHeight * 1.1 / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(queuedSongIds(), ['song-a', 'song-a', 'song-b']);
    // The first copy was playing, and still is.
    expect(engine.currentState.queue.currentIndex, 0);
  });

  testWidgets('the screen-reader Move up action moves the copy it is on', (
    tester,
  ) async {
    await pumpQueue(tester, const [_a, _b, _a], startIndex: 1);

    final semantics = tester.widget<Semantics>(
      find
          .descendant(of: row('song-a#2'), matching: find.byType(Semantics))
          .first,
    );
    final moveUp = semantics.properties.customSemanticsActions!.entries
        .singleWhere((entry) => entry.key.label == 'Move up')
        .value;
    moveUp();
    await settle(tester);

    expect(queuedSongIds(), ['song-a', 'song-a', 'song-b']);
    // B was playing at index 1; it is still the playing song.
    expect(engine.currentState.queue.currentTrack?.songId, 'song-b');
    expect(engine.currentState.queue.currentIndex, 2);
  });

  testWidgets('tapping the later copy plays that copy', (tester) async {
    await pumpQueue(tester, const [_a, _b, _a]);

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-track-open-song-a#2')),
    );
    await settle(tester);

    expect(engine.currentState.queue.currentIndex, 2);
    expect(engine.currentState.queue.currentTrack?.songId, 'song-a');
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-a#2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-a')),
      findsNothing,
    );
  });

  group('SN-50 A2: Clear queue', () {
    final clear = find.byKey(const ValueKey<String>('playback-queue-clear'));
    final confirm = find.byKey(
      const ValueKey<String>('playback-queue-clear-confirm'),
    );

    bool clearEnabled(WidgetTester tester) =>
        tester.widget<IconButton>(clear).onPressed != null;

    testWidgets('asks first; Cancel removes nothing', (tester) async {
      await pumpQueue(tester, const [_a, _b], startIndex: 0);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('Clear queue?'), findsOneWidget);
      expect(find.textContaining('1 other song'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(queuedSongIds(), ['song-a', 'song-b']);
    });

    testWidgets('keeps only the song playing, at its place and still '
        'playing', (tester) async {
      await pumpQueue(tester, const [_a, _b, _a], startIndex: 1);
      await tester.runAsync(() async {
        await engine.seek(const Duration(minutes: 1));
        await engine.play();
      });
      await settle(tester);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await settle(tester);

      expect(queuedSongIds(), ['song-b']);
      expect(engine.currentState.queue.currentIndex, 0);
      expect(engine.currentState.position, const Duration(minutes: 1));
      expect(engine.currentState.isPlaying, isTrue);
      expect(clearEnabled(tester), isFalse);
    });

    testWidgets('a later copy of a song queued twice is the one kept', (
      tester,
    ) async {
      await pumpQueue(tester, const [_a, _b, _a], startIndex: 2);

      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await settle(tester);

      expect(queuedSongIds(), ['song-a']);
      expect(engine.currentState.queue.currentIndex, 0);
      expect(engine.currentState.status, isNot(PlaybackStatus.idle));
    });

    testWidgets('nothing to clear with one song', (tester) async {
      await pumpQueue(tester, const [_a]);

      expect(clearEnabled(tester), isFalse);
    });
  });
}
