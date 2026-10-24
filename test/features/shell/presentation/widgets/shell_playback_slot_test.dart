import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/presentation/widgets/shell_playback_slot.dart';

class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({PlaybackState? initialState})
    : _state = initialState ?? const PlaybackState();

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state;

  int playCalls = 0;
  int pauseCalls = 0;
  int previousCalls = 0;
  int nextCalls = 0;

  Duration? lastSeekPosition;
  bool? lastShuffleEnabled;
  PlaybackRepeatMode? lastRepeatMode;

  int? lastSkippedToIndex;
  int? lastRemovedIndex;
  int? lastMoveOldIndex;
  int? lastMoveNewIndex;

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> skipPrevious() async {
    previousCalls++;
  }

  @override
  Future<void> skipNext() async {
    nextCalls++;
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
  }

  @override
  Future<void> skipToIndex(int index) async {
    lastSkippedToIndex = index;
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {
    lastRemovedIndex = index;
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) async {
    lastMoveOldIndex = oldIndex;
    lastMoveNewIndex = newIndex;
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    lastRepeatMode = mode;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

const track1 = PlaybackTrack(
  songId: 'song-1',
  title: 'First Song',
  artistId: 'artist-1',
  artistName: 'First Artist',
  albumId: 'album-1',
  albumTitle: 'First Album',
  filePath: '/music/first.mp3',
  duration: Duration(minutes: 3),
);

const track2 = PlaybackTrack(
  songId: 'song-2',
  title: 'Second Song',
  artistId: 'artist-2',
  artistName: 'Second Artist',
  albumId: 'album-2',
  albumTitle: 'Second Album',
  filePath: '/music/second.mp3',
  duration: Duration(minutes: 4),
);

const track3 = PlaybackTrack(
  songId: 'song-3',
  title: 'Third Song',
  artistId: 'artist-3',
  artistName: 'Third Artist',
  albumId: 'album-3',
  albumTitle: 'Third Album',
  filePath: '/music/third.mp3',
  duration: Duration(minutes: 5),
);
Widget buildSubject(FakePlaybackEngine engine, {ThemeData? theme}) {
  final coordinator = PlaybackCoordinator(engine: engine);
  final stateController = PlaybackStateController(coordinator: coordinator);

  return MultiProvider(
    providers: [
      Provider<PlaybackCoordinator>.value(value: coordinator),
      ChangeNotifierProvider<PlaybackStateController>.value(
        value: stateController,
      ),
      ChangeNotifierProvider<LyricsController?>.value(value: null),
    ],
    child: MaterialApp(
      theme: theme,
      home: const Scaffold(bottomNavigationBar: ShellPlaybackSlot()),
    ),
  );
}

void main() {
  testWidgets('is empty when there is no current track', (tester) async {
    final engine = FakePlaybackEngine();

    await tester.pumpWidget(buildSubject(engine));

    expect(
      find.byKey(const ValueKey<String>('shell-playback-slot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mini-player-empty')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('mini-player')), findsNothing);

    await engine.dispose();
  });

  testWidgets('shows current track metadata and artwork fallback', (
    tester,
  ) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('First Artist'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('mini-player-artwork-fallback')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('updates from playback state changes', (tester) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
        status: PlaybackStatus.playing,
        position: Duration(minutes: 1),
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Second Artist'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('play pause button delegates to coordinator', (tester) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(
      find.byKey(const ValueKey<String>('mini-player-play-pause')),
    );
    await tester.pump();

    expect(engine.playCalls, 1);
    expect(engine.pauseCalls, 0);

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('mini-player-play-pause')),
    );
    await tester.pump();

    expect(engine.playCalls, 1);
    expect(engine.pauseCalls, 1);

    await engine.dispose();
  });

  testWidgets('previous and next reflect queue boundaries', (tester) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    final previous = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('mini-player-previous')),
    );
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('mini-player-next')),
    );

    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-next')));
    await tester.pump();

    expect(engine.nextCalls, 1);

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pump();

    final updatedPrevious = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('mini-player-previous')),
    );
    final updatedNext = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('mini-player-next')),
    );

    expect(updatedPrevious.onPressed, isNotNull);
    expect(updatedNext.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('mini-player-previous')),
    );
    await tester.pump();

    expect(engine.previousCalls, 1);

    await engine.dispose();
  });

  testWidgets('shows loading state and disables play pause', (tester) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.loading,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('mini-player-play-pause')),
    );

    expect(button.onPressed, isNull);

    await engine.dispose();
  });

  testWidgets('progress reflects playback position', (tester) async {
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.playing,
        position: Duration(minutes: 1),
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    final progress = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('mini-player-progress')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );

    expect(progress.value, closeTo(1 / 3, 0.001));

    await engine.dispose();
  });

  testWidgets('an unreadable song is explained in the app (SN-44)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );
    addTearDown(engine.dispose);
    await tester.pumpWidget(buildSubject(engine));

    const failed = PlaybackState(
      queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
      status: PlaybackStatus.failed,
      duration: Duration(minutes: 3),
      errorMessage: '(0) Source error',
    );
    engine.emit(failed);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('mini-player-error')),
      findsOneWidget,
    );
    expect(find.text('Song unavailable'), findsOneWidget);
    // Recoverable: the listener can still move on.
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('mini-player-next')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('now-playing-error')),
      findsOneWidget,
    );
    expect(
      find.textContaining('may have been moved or deleted'),
      findsOneWidget,
    );
    // Engine error text is technical and may contain file paths.
    expect(find.textContaining('Source error'), findsNothing);

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('now-playing-error')),
      findsNothing,
    );
    expect(find.text('Second Song'), findsWidgets);
  });

  testWidgets('repeat button announces the current mode (SN-44)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );
    addTearDown(engine.dispose);
    await tester.pumpWidget(buildSubject(engine));
    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    String announced() {
      final data = tester
          .getSemantics(
            find.byKey(const ValueKey<String>('now-playing-repeat')),
          )
          .getSemanticsData();
      return [data.label, data.tooltip].where((s) => s.isNotEmpty).join(' ');
    }

    for (final (mode, expected) in [
      (PlaybackRepeatMode.off, 'Repeat off'),
      (PlaybackRepeatMode.all, 'Repeat all'),
      (PlaybackRepeatMode.one, 'Repeat one'),
      (PlaybackRepeatMode.off, 'Repeat off'),
    ]) {
      engine.emit(
        PlaybackState(
          queue: const PlaybackQueue(tracks: [track1], currentIndex: 0),
          status: PlaybackStatus.playing,
          duration: const Duration(minutes: 3),
          repeatMode: mode,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(announced(), expected, reason: 'mode $mode');
    }

    semantics.dispose();
  });

  group('follows the playback authority (SN-44)', () {
    testWidgets('position updates refresh progress with no interaction', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engine = FakePlaybackEngine(
        initialState: const PlaybackState(
          queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 3),
        ),
      );
      addTearDown(engine.dispose);
      await tester.pumpWidget(buildSubject(engine));

      double miniProgress() => tester
          .widget<LinearProgressIndicator>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('mini-player-progress')),
              matching: find.byType(LinearProgressIndicator),
            ),
          )
          .value!;

      engine.emit(
        const PlaybackState(
          queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
          status: PlaybackStatus.playing,
          position: Duration(seconds: 90),
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(miniProgress(), closeTo(0.5, 0.001));

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pumpAndSettle();
      engine.emit(
        const PlaybackState(
          queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
          status: PlaybackStatus.playing,
          position: Duration(seconds: 125),
          duration: Duration(minutes: 3),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('now-playing-elapsed')),
            )
            .data,
        '2:05',
      );
    });

    testWidgets('Next follows the player across shuffle and repeat', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Last in list order, but the player (shuffle or repeat all) still
      // has a next song.
      final engine = FakePlaybackEngine(
        initialState: const PlaybackState(
          queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 3),
          nextAvailable: true,
          previousAvailable: false,
        ),
      );
      addTearDown(engine.dispose);
      await tester.pumpWidget(buildSubject(engine));

      bool enabled(String key) =>
          tester
              .widget<IconButton>(find.byKey(ValueKey<String>(key)))
              .onPressed !=
          null;

      expect(enabled('mini-player-next'), isTrue);
      expect(enabled('mini-player-previous'), isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pumpAndSettle();
      expect(enabled('now-playing-next'), isTrue);
      expect(enabled('now-playing-previous'), isFalse);

      // First in list order, but the shuffle order is exhausted.
      engine.emit(
        const PlaybackState(
          queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 3),
          nextAvailable: false,
          previousAvailable: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(enabled('now-playing-next'), isFalse);
      expect(enabled('now-playing-previous'), isTrue);
    });
  });

  testWidgets('mini player opens full now playing page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('now-playing-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now-playing-artwork')),
      findsOneWidget,
    );
    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('First Artist'), findsOneWidget);
    expect(find.text('First Album'), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('now playing closes back to shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('now-playing-page')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('now playing controls delegate playback actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('now-playing-play-pause')),
    );
    await tester.pump();

    expect(engine.playCalls, 1);

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-next')));
    await tester.pump();

    expect(engine.nextCalls, 1);

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-shuffle')));
    await tester.pump();

    expect(engine.lastShuffleEnabled, isTrue);

    await engine.dispose();
  });

  testWidgets('repeat cycles off to all to one to off', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
        repeatMode: PlaybackRepeatMode.off,
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-repeat')));
    await tester.pump();

    expect(engine.lastRepeatMode, PlaybackRepeatMode.all);

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
        repeatMode: PlaybackRepeatMode.all,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-repeat')));
    await tester.pump();

    expect(engine.lastRepeatMode, PlaybackRepeatMode.one);

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
        repeatMode: PlaybackRepeatMode.one,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-repeat')));
    await tester.pump();

    expect(engine.lastRepeatMode, PlaybackRepeatMode.off);

    await engine.dispose();
  });

  testWidgets('now playing seek delegates selected position', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.playing,
        position: Duration(minutes: 1),
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('now-playing-seek')),
    );

    slider.onChanged!(90000);
    await tester.pump();

    expect(engine.lastSeekPosition, const Duration(seconds: 90));

    await engine.dispose();
  });

  testWidgets('now playing reflects live track and playback state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
        status: PlaybackStatus.playing,
        position: Duration(minutes: 1),
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Second Artist'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('now-playing-play-pause')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('mini player queue button opens queue page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('playback-queue-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('playback-queue-list')),
      findsOneWidget,
    );
    expect(find.text('First Song'), findsWidgets);
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Third Song'), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('now playing queue button opens queue page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-queue')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('playback-queue-page')),
      findsOneWidget,
    );

    await engine.dispose();
  });

  testWidgets('queue highlights the current track', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 1),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('queue-current-song-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-3')),
      findsNothing,
    );

    expect(
      find.byKey(const ValueKey<String>('queue-current-summary')),
      findsOneWidget,
    );

    await engine.dispose();
  });

  testWidgets('queue track tap delegates skip to index', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('queue-track-open-song-3')),
    );
    await tester.pump();

    expect(engine.lastSkippedToIndex, 2);

    await engine.dispose();
  });

  testWidgets('queue remove delegates the correct index', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('queue-remove-song-2')));
    await tester.pump();

    expect(engine.lastRemovedIndex, 1);

    await engine.dispose();
  });

  testWidgets('queue reorder delegates adjusted final index downward', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey<String>('playback-queue-list')),
    );

    list.onReorderItem!(0, 2);
    await tester.pump();

    expect(engine.lastMoveOldIndex, 0);
    expect(engine.lastMoveNewIndex, 2);

    await engine.dispose();
  });

  testWidgets('queue reorder delegates adjusted final index upward', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey<String>('playback-queue-list')),
    );

    list.onReorderItem!(2, 0);
    await tester.pump();

    expect(engine.lastMoveOldIndex, 2);
    expect(engine.lastMoveNewIndex, 0);

    await engine.dispose();
  });

  testWidgets('queue reflects live queue state updates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2, track3], currentIndex: 0),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('queue-current-song-1')),
      findsOneWidget,
    );

    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 1),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('queue-current-song-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('queue-track-song-3')),
      findsNothing,
    );

    await engine.dispose();
  });

  group('Sonus themes', () {
    const playing = PlaybackState(
      queue: PlaybackQueue(tracks: [track1, track2], currentIndex: 0),
      status: PlaybackStatus.playing,
      position: Duration(minutes: 1),
      duration: Duration(minutes: 3),
    );

    for (final themeId in SonusThemeId.values) {
      testWidgets('mini-player inherits ${themeId.label} tokens', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final theme = SonusThemeFactory.build(
          SonusAppearanceSpec(themeId: themeId),
        );
        final colors = theme.extension<SonusColors>()!;
        final engine = FakePlaybackEngine(initialState: playing);

        await tester.pumpWidget(buildSubject(engine, theme: theme));
        await tester.pump();

        expect(tester.takeException(), isNull);

        final container = tester.widget<Container>(
          find.byKey(const ValueKey<String>('mini-player')),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.raisedSurface);

        final progress = tester.widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('mini-player-progress')),
            matching: find.byType(LinearProgressIndicator),
          ),
        );
        expect(progress.color, colors.progressActive);
        expect(progress.backgroundColor, colors.progressInactive);

        final playPause = tester.widget<IconButton>(
          find.byKey(const ValueKey<String>('mini-player-play-pause')),
        );
        expect(
          playPause.style!.backgroundColor!.resolve(<WidgetState>{}),
          colors.playbackControl,
        );
        expect(
          find.byKey(const ValueKey<String>('mini-player-artwork-fallback')),
          findsOneWidget,
        );

        final next = find.byKey(const ValueKey<String>('mini-player-next'));
        expect(tester.getSize(next).height, greaterThanOrEqualTo(44));

        await engine.dispose();
      });
    }

    testWidgets('reduced motion opens Now Playing without a transition', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(initialState: playing);

      await tester.pumpWidget(
        buildSubject(
          engine,
          theme: SonusThemeFactory.build(
            const SonusAppearanceSpec(reduceMotion: true),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pump();
      await tester.pump();

      final page = find.byKey(const ValueKey<String>('now-playing-page'));
      final route = ModalRoute.of(tester.element(page))!;
      expect(route.animation!.status, AnimationStatus.completed);

      await engine.dispose();
    });
  });

  testWidgets('now playing lyrics button opens lyrics page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(tracks: [track1], currentIndex: 0),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );

    await tester.pumpWidget(buildSubject(engine));

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('now-playing-page')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('now-playing-lyrics')),
    );

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-lyrics')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey<String>('lyrics-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('lyrics-initializing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('lyrics-track-title')),
      findsOneWidget,
    );
    expect(find.text('First Song'), findsWidgets);

    await engine.dispose();
  });
}
