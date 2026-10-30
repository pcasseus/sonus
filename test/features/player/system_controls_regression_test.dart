// SN-50 Session D: the system player's Shuffle and Repeat, and the end of
// the queue, through the real engine (with a simulated just_audio player),
// the coordinator and the media session.
import 'dart:convert';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_preferences_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_restoration_controller.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_state_mapper.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/data/services/playback_preferences_store.dart';
import 'package:sonus_next/features/player/data/services/playback_session_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_session_snapshot.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';

import 'data/engines/simulated_just_audio_player.dart';

PlaybackTrack _track(String id) => PlaybackTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
);

void main() {
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late int releases;
  late SonusAudioHandler handler;

  setUp(() {
    player = SimulatedJustAudioPlayer();
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
    releases = 0;
    handler = SonusAudioHandler(
      artworkExists: (_) => false,
      releaseForeground: () async => releases++,
    )..attach(coordinator);
  });

  tearDown(() async {
    handler.detach(coordinator);
    await engine.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('system Shuffle and Repeat are remembered like in-app changes '
      '(D-Q13)', () async {
    final storage = <String, String>{};
    PlaybackPreferencesStore store() => PlaybackPreferencesStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
    );
    final preferences = PlaybackPreferencesController(
      store: store(),
      coordinator: coordinator,
    );
    addTearDown(preferences.dispose);
    await preferences.load();
    await preferences.setRememberShuffleAndRepeat(true);
    await engine.loadQueue([_track('a'), _track('b')], autoPlay: true);
    await settle();

    await handler.customAction(MediaSessionStateMapper.shuffleAction);
    await handler.customAction(MediaSessionStateMapper.repeatAction);
    await settle();

    expect(engine.currentState.shuffleEnabled, isTrue);
    expect(engine.currentState.repeatMode, PlaybackRepeatMode.all);
    final saved = (await store().load()).preferences;
    expect(saved.shuffleEnabled, isTrue);
    expect(saved.repeatMode, PlaybackRepeatMode.all);
    expect(handler.playbackState.value.controls.map((c) => c.label).skip(3), [
      'Shuffle on',
      'Repeat all',
    ]);
  });

  group('the end of the queue with Repeat off (D-Q16)', () {
    late List<PlaybackStatus> statuses;

    Future<void> playToTheEnd() async {
      statuses = [];
      engine.states.listen((state) => statuses.add(state.status));
      await engine.loadQueue(
        [_track('a'), _track('b')],
        startIndex: 1,
        autoPlay: true,
      );
      await settle();
      player.advanceTo(const Duration(minutes: 3));
      player.complete();
      await settle();
    }

    test('stays paused on the last song with its controls and queue', () async {
      await playToTheEnd();

      // Sonus reports completion once, as before, so listening history
      // closes the last song's session exactly once.
      expect(
        statuses.where((s) => s == PlaybackStatus.completed),
        hasLength(1),
      );
      expect(engine.currentState.queue.currentTrack?.songId, 'b');
      expect(engine.currentState.queue.length, 2);
      expect(engine.currentState.position, const Duration(minutes: 3));

      final state = handler.playbackState.value;
      expect(state.processingState, media.AudioProcessingState.ready);
      expect(state.playing, isFalse);
      expect(state.controls, hasLength(5));
      expect(handler.mediaItem.value?.id, 'b');
      expect(releases, 0, reason: 'the notification stays');
    });

    final playCommands = <String, Future<void> Function()>{
      'Now Playing or the mini player': () => coordinator.togglePlayPause(),
      'the notification or media session': () => handler.play(),
      'a Bluetooth media button': () => handler.click(),
    };

    for (final MapEntry(key: source, value: pressPlay)
        in playCommands.entries) {
      test('Play from $source replays the last song from 0:00 (R4)', () async {
        await playToTheEnd();

        await pressPlay();
        await settle();

        final state = engine.currentState;
        expect(player.audible, isTrue);
        expect(state.status, PlaybackStatus.playing);
        expect(state.position, Duration.zero);
        expect(state.queue.currentTrack?.songId, 'b');
        expect(state.queue.tracks.map((t) => t.songId), ['a', 'b']);
        expect(state.repeatMode, PlaybackRepeatMode.off);
        expect(state.shuffleEnabled, isFalse);
        expect(handler.playbackState.value.playing, isTrue);
      });
    }

    test('replaying keeps shuffle and repeat as they were', () async {
      await engine.setShuffleEnabled(true);
      await playToTheEnd();

      await coordinator.play();
      await settle();

      expect(player.audible, isTrue);
      expect(engine.currentState.queue.currentTrack?.songId, 'b');
      expect(engine.currentState.shuffleEnabled, isTrue);
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.off);
    });

    test('Play mid-song still resumes where it was', () async {
      await engine.loadQueue([_track('a'), _track('b')], startIndex: 1);
      await settle();
      await engine.seek(const Duration(minutes: 1));
      await settle();

      await coordinator.play();
      await settle();

      expect(player.audible, isTrue);
      expect(engine.currentState.position, const Duration(minutes: 1));
    });

    test('Play 5 s before the end of the last song resumes there', () async {
      await engine.loadQueue([_track('a'), _track('b')], startIndex: 1);
      await settle();
      await engine.seek(const Duration(minutes: 2, seconds: 55));
      await settle();
      final seeks = <Duration>[];
      engine.states.listen((state) => seeks.add(state.position));

      await coordinator.play();
      await settle();

      expect(player.audible, isTrue);
      expect(seeks, isNot(contains(Duration.zero)));
      expect(
        engine.currentState.position,
        const Duration(minutes: 2, seconds: 55),
      );
    });
  });

  group('a finished queue across restarts (R4)', () {
    LibraryTrack libraryTrack(String id) => LibraryTrack(
      songId: id,
      title: 'Song $id',
      artistId: 'artist',
      artistName: 'Artist',
      albumId: 'album',
      albumTitle: 'Album',
      albumEditionId: 'edition',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 10, 1),
      isAvailable: true,
      filePath: '/music/$id.mp3',
    );

    late Map<String, String> storage;

    PlaybackSessionStore store() => PlaybackSessionStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
      remove: (key) async => storage.remove(key),
    );

    setUp(() => storage = {});

    /// A new process: fresh player, engine and coordinator restoring the
    /// stored session. Returns the restored player and engine.
    Future<(SimulatedJustAudioPlayer, JustAudioPlaybackEngine)>
    restart() async {
      final nextPlayer = SimulatedJustAudioPlayer();
      final nextEngine = JustAudioPlaybackEngine(
        audioPlayer: nextPlayer,
        configureAudioSession: () async {},
      );
      addTearDown(nextEngine.dispose);
      final restorer = PlaybackRestorationController(
        store: store(),
        coordinator: PlaybackCoordinator(engine: nextEngine),
      );
      addTearDown(restorer.dispose);

      final outcome = await restorer.restore(
        () async => [
          for (final id in ['a', 'b', 'c']) libraryTrack(id),
        ],
      );
      await settle();
      expect(outcome, PlaybackRestoreOutcome.restored);
      return (nextPlayer, nextEngine);
    }

    test('restored just short of the end, Play replays from 0:00', () async {
      storage[PlaybackSessionStore.sessionKey] = jsonEncode(
        const PlaybackSessionSnapshot(
          songIds: ['a', 'b', 'c'],
          currentIndex: 2,
          position: Duration(minutes: 2, seconds: 59, milliseconds: 600),
        ).toJson(),
      );
      final (restoredPlayer, restoredEngine) = await restart();
      expect(
        restoredEngine.currentState.position,
        const Duration(minutes: 2, seconds: 59, milliseconds: 600),
      );
      expect(restoredPlayer.audible, isFalse);

      await PlaybackCoordinator(engine: restoredEngine).play();
      await settle();

      expect(restoredPlayer.audible, isTrue);
      expect(restoredEngine.currentState.queue.currentTrack?.songId, 'c');
      expect(restoredEngine.currentState.position, Duration.zero);
    });

    test('stays paused on the last song through two restarts, then Play '
        'replays it from 0:00', () async {
      final recorder = PlaybackRestorationController(
        store: store(),
        coordinator: coordinator,
      );
      await recorder.restore(() async => const []);
      await engine.loadQueue(
        [_track('a'), _track('b'), _track('c')],
        startIndex: 2,
        autoPlay: true,
      );
      await settle();
      player.advanceTo(const Duration(minutes: 3));
      player.complete();
      await settle();
      await recorder.saveNow();
      recorder.dispose();

      expect(storage, isNotEmpty, reason: 'the finished session is kept');

      await restart();
      final (lastPlayer, lastEngine) = await restart();

      final restored = lastEngine.currentState;
      expect(restored.queue.tracks.map((t) => t.songId), ['a', 'b', 'c']);
      expect(restored.queue.currentTrack?.songId, 'c');
      expect(restored.position, const Duration(minutes: 3));
      expect(restored.isPlaying, isFalse);
      expect(lastPlayer.audible, isFalse, reason: 'no autoplay on restore');

      await PlaybackCoordinator(engine: lastEngine).togglePlayPause();
      await settle();

      final replay = lastEngine.currentState;
      expect(lastPlayer.audible, isTrue);
      expect(replay.queue.currentTrack?.songId, 'c');
      expect(replay.position, Duration.zero);
      expect(replay.queue.tracks.map((t) => t.songId), ['a', 'b', 'c']);
    });
  });
}
