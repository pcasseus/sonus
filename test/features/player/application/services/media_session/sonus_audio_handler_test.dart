import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import 'media_session_test_support.dart';

void main() {
  late DateTime clock;
  late List<(String, int)> logs;
  late RecordingEngine engine;
  late PlaybackCoordinator coordinator;
  late SonusAudioHandler handler;

  setUp(() {
    clock = DateTime.utc(2026, 10, 24, 12);
    logs = [];
    engine = RecordingEngine();
    coordinator = PlaybackCoordinator(engine: engine);
    handler = SonusAudioHandler(
      artworkExists: (_) => true,
      now: () => clock,
      log: (message, {level = 800}) => logs.add((message, level)),
    );
  });

  tearDown(() => engine.dispose());

  Future<void> emit(PlaybackState state) async {
    engine.emit(state);
    await pumpEventQueue();
  }

  test('attaching publishes the current state at once', () {
    engine.emit(queuedState(index: 1));
    handler.attach(coordinator);

    expect(handler.mediaItem.value!.id, 'b');
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.queue.value.map((item) => item.id), ['a', 'b', 'c']);
  });

  group('commands use the single playback authority', () {
    setUp(() => handler.attach(coordinator));

    test('transport controls reach the engine', () async {
      await handler.play();
      await handler.pause();
      await handler.skipToNext();
      await handler.skipToPrevious();
      await handler.seek(const Duration(seconds: 30));
      await handler.skipToQueueItem(2);

      expect(engine.commands, [
        'play',
        'pause',
        'skipNext',
        'skipPrevious',
        'seek:30',
        'skipToIndex:2',
      ]);
    });

    test('shuffle and repeat use Sonus semantics', () async {
      await handler.setShuffleMode(media.AudioServiceShuffleMode.all);
      await handler.setShuffleMode(media.AudioServiceShuffleMode.none);
      await handler.setRepeatMode(media.AudioServiceRepeatMode.one);
      await handler.setRepeatMode(media.AudioServiceRepeatMode.group);
      await handler.setRepeatMode(media.AudioServiceRepeatMode.none);

      expect(engine.commands, [
        'shuffle:true',
        'shuffle:false',
        'repeat:one',
        'repeat:all',
        'repeat:off',
      ]);
    });

    test('headset buttons map to play/pause and skipping', () async {
      await emit(queuedState(status: PlaybackStatus.paused));
      await handler.click();
      await emit(queuedState());
      await handler.click();
      await handler.click(media.MediaButton.next);
      await handler.click(media.MediaButton.previous);

      expect(engine.commands, ['play', 'pause', 'skipNext', 'skipPrevious']);
    });

    test('explicit Play and Pause never toggle (SN-44)', () async {
      // Android delivers dedicated PLAY/PAUSE keys (cars, Bluetooth) as
      // play()/pause() through the patched plugin.
      await emit(queuedState());
      await handler.play();
      await emit(queuedState(status: PlaybackStatus.paused));
      await handler.pause();

      expect(engine.commands, ['play', 'pause']);
    });

    test('Stop ends playback and clears the notification', () async {
      await emit(queuedState());

      await handler.stop();

      expect(engine.commands, ['stop']);
      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.idle,
      );
    });

    test('a failing command is logged, never thrown at Android', () async {
      engine.failWith = StateError('engine disposed');

      await handler.play();

      expect(logs.single.$2, 900);
      expect(logs.single.$1, contains('play'));
    });

    test('the handler never loads or edits the queue itself', () async {
      await emit(queuedState());
      await handler.play();
      await handler.skipToNext();
      await handler.stop();

      expect(
        engine.commands.where(
          (c) =>
              c == 'loadQueue' ||
              c.startsWith('insert') ||
              c.startsWith('remove') ||
              c.startsWith('move') ||
              c.startsWith('append'),
        ),
        isEmpty,
      );
    });
  });

  group('publishing', () {
    test('ordinary progress is not republished', () async {
      handler.attach(coordinator);
      await emit(queuedState(position: const Duration(seconds: 10)));
      final published = <media.PlaybackState>[];
      final subscription = handler.playbackState.skip(1).listen(published.add);

      for (var second = 11; second <= 15; second++) {
        clock = clock.add(const Duration(seconds: 1));
        await emit(queuedState(position: Duration(seconds: second)));
      }

      expect(published, isEmpty);
      await subscription.cancel();
    });

    test('a seek is published immediately', () async {
      handler.attach(coordinator);
      await emit(queuedState(position: const Duration(seconds: 10)));

      clock = clock.add(const Duration(seconds: 1));
      await emit(queuedState(position: const Duration(seconds: 90)));

      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 90),
      );
    });

    test('a track change updates the metadata and the index', () async {
      handler.attach(coordinator);
      await emit(queuedState());

      await emit(queuedState(index: 1));

      expect(handler.mediaItem.value!.id, 'b');
      expect(handler.playbackState.value.queueIndex, 1);
    });

    test('pausing, buffering and errors are published', () async {
      handler.attach(coordinator);
      await emit(queuedState());

      await emit(queuedState(status: PlaybackStatus.paused));
      expect(handler.playbackState.value.playing, isFalse);

      await emit(queuedState(status: PlaybackStatus.loading));
      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.buffering,
      );

      await emit(queuedState(status: PlaybackStatus.failed));
      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.error,
      );
    });

    test('artwork appearing later updates the notification', () async {
      var artExists = false;
      final artHandler = SonusAudioHandler(
        artworkExists: (_) => artExists,
        now: () => clock,
      );
      final state = queuedState(
        tracks: [mediaTrack('a', artworkPath: '/art/a.png')],
      );
      artHandler.attach(coordinator);
      await emit(state);
      expect(artHandler.mediaItem.value!.artUri, isNull);

      artExists = true;
      await emit(
        queuedState(
          status: PlaybackStatus.paused,
          tracks: [mediaTrack('a', artworkPath: '/art/a.png')],
        ),
      );

      expect(artHandler.mediaItem.value!.artUri, Uri.file('/art/a.png'));
    });

    test('clearing the queue removes the notification', () async {
      handler.attach(coordinator);
      await emit(queuedState());

      await emit(const PlaybackState());

      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.idle,
      );
      expect(handler.mediaItem.value, isNull);
    });
  });

  group('rebinding after a restore reload', () {
    test('commands follow the newest coordinator', () async {
      handler.attach(coordinator);
      final newEngine = RecordingEngine();
      addTearDown(newEngine.dispose);

      handler.attach(PlaybackCoordinator(engine: newEngine));
      await handler.play();

      expect(engine.commands, isEmpty);
      expect(newEngine.commands, ['play']);
    });

    test('the old scope detaching late does not unbind the new one', () async {
      handler.attach(coordinator);
      final newEngine = RecordingEngine();
      addTearDown(newEngine.dispose);
      final newCoordinator = PlaybackCoordinator(engine: newEngine);

      // Flutter mounts the new playback scope before disposing the old.
      handler.attach(newCoordinator);
      handler.detach(coordinator);

      expect(handler.coordinator, same(newCoordinator));
      newEngine.emit(queuedState(index: 2));
      await pumpEventQueue();
      expect(handler.mediaItem.value!.id, 'c');

      // The old engine's states no longer reach the session.
      engine.emit(queuedState(index: 0));
      await pumpEventQueue();
      expect(handler.mediaItem.value!.id, 'c');
    });

    test('detaching the current coordinator clears the session', () async {
      handler.attach(coordinator);
      await emit(queuedState());

      handler.detach(coordinator);

      expect(handler.coordinator, isNull);
      expect(
        handler.playbackState.value.processingState,
        media.AudioProcessingState.idle,
      );
      expect(handler.mediaItem.value, isNull);
    });

    test('commands while detached are ignored and logged', () async {
      await handler.play();

      expect(engine.commands, isEmpty);
      expect(logs.single.$1, contains('not ready'));
    });
  });

  group('releasing the notification when the session ends', () {
    late int releases;
    late SonusAudioHandler releasing;

    setUp(() {
      releases = 0;
      releasing = SonusAudioHandler(
        artworkExists: (_) => true,
        now: () => clock,
        log: (message, {level = 800}) => logs.add((message, level)),
        releaseForeground: () async => releases++,
      )..attach(coordinator);
    });

    test('attaching while nothing is queued releases nothing', () {
      expect(releases, 0);
    });

    test('pausing, buffering and errors keep the notification', () async {
      await emit(queuedState());
      await emit(queuedState(status: PlaybackStatus.paused));
      await emit(queuedState(status: PlaybackStatus.loading));
      await emit(queuedState(status: PlaybackStatus.failed));
      await emit(queuedState(status: PlaybackStatus.paused));

      expect(releases, 0);
    });

    test('a completed queue releases it once', () async {
      await emit(queuedState());
      await emit(queuedState(status: PlaybackStatus.completed));
      await emit(const PlaybackState());

      expect(releases, 1);
    });

    test('Stop releases it once', () async {
      await emit(queuedState(status: PlaybackStatus.paused));

      await releasing.stop();
      await emit(queuedState(status: PlaybackStatus.idle));

      expect(releases, 1);
    });

    test('playing again after a release can release again', () async {
      await emit(queuedState());
      await emit(const PlaybackState());
      await emit(queuedState());
      await emit(const PlaybackState());

      expect(releases, 2);
    });

    test('a restore reload that replaces playback releases it', () async {
      await emit(queuedState());
      final newEngine = RecordingEngine();
      addTearDown(newEngine.dispose);
      final newCoordinator = PlaybackCoordinator(engine: newEngine);

      releasing.attach(newCoordinator);
      releasing.detach(coordinator);

      expect(releases, 1);
      expect(releasing.mediaItem.value, isNull);
    });

    test('a reload onto restored playback keeps the notification', () async {
      await emit(queuedState());
      final newEngine = RecordingEngine()
        ..emit(queuedState(status: PlaybackStatus.paused));
      addTearDown(newEngine.dispose);

      releasing.attach(PlaybackCoordinator(engine: newEngine));

      expect(releases, 0);
      expect(releasing.mediaItem.value!.id, 'a');
    });

    test('detaching a playing coordinator releases it', () async {
      await emit(queuedState());

      releasing.detach(coordinator);

      expect(releases, 1);
    });

    test('a failed release is logged, never thrown', () async {
      final failing = SonusAudioHandler(
        artworkExists: (_) => true,
        now: () => clock,
        log: (message, {level = 800}) => logs.add((message, level)),
        releaseForeground: () async => throw StateError('no activity'),
      )..attach(coordinator);
      await emit(queuedState());

      await emit(const PlaybackState());

      expect(
        failing.playbackState.value.processingState,
        media.AudioProcessingState.idle,
      );
      expect(logs.single.$1, contains('could not be released'));
      expect(logs.single.$2, 900);
    });
  });
}
