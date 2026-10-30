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

  group('SN-50 A1: Repeat One repeats only a song that finishes', () {
    Future<void> load(List<String> ids, {int start = 0}) async {
      await engine.loadQueue([
        for (final id in ids) _track(id),
      ], startIndex: start);
      await settle();
      await engine.setRepeatMode(PlaybackRepeatMode.one);
      await settle();
    }

    String? current() => engine.currentState.queue.currentTrack?.songId;

    test('Next moves to the next song; Repeat One stays on for it', () async {
      await load(['a', 'b', 'c']);

      await coordinator.skipNext();
      await settle();

      expect(engine.currentState.queue.currentIndex, 1);
      expect(current(), 'b');
      expect(engine.currentState.position, Duration.zero);
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('Next on the last song stays on it, as without Repeat One', () async {
      await load(['a', 'b'], start: 1);

      await coordinator.skipNext();
      await settle();

      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('Previous early in a song goes to the previous song', () async {
      await load(['a', 'b', 'c'], start: 2);

      await coordinator.skipPrevious();
      await settle();

      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('Previous later in a song restarts it; on the first song it '
        'restarts too', () async {
      await load(['a', 'b'], start: 1);
      await engine.seek(const Duration(seconds: 40));
      await settle();

      await coordinator.skipPrevious();
      await settle();
      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.position, Duration.zero);

      await engine.skipToIndex(0);
      await settle();
      await coordinator.skipPrevious();
      await settle();
      expect(engine.currentState.queue.currentIndex, 0);
      expect(engine.currentState.position, Duration.zero);
    });

    test('a song queued twice: Next walks to each copy in turn', () async {
      await load(['a', 'b', 'a']);

      await coordinator.skipNext();
      await settle();
      await coordinator.skipNext();
      await settle();

      expect(engine.currentState.queue.currentIndex, 2);
      expect(current(), 'a');
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('the system Next and Previous buttons behave the same', () async {
      await load(['a', 'b', 'c'], start: 1);

      await handler.skipToNext();
      await settle();
      expect(engine.currentState.queue.currentIndex, 2);

      await handler.skipToPrevious();
      await settle();
      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('Repeat All still wraps from the last song; Repeat Off still '
        'stops there', () async {
      await engine.loadQueue([_track('a'), _track('b')], startIndex: 1);
      await settle();

      await engine.setRepeatMode(PlaybackRepeatMode.all);
      await coordinator.skipNext();
      await settle();
      expect(engine.currentState.queue.currentIndex, 0);

      await engine.skipToIndex(1);
      await settle();
      await engine.setRepeatMode(PlaybackRepeatMode.off);
      await coordinator.skipNext();
      await settle();
      expect(engine.currentState.queue.currentIndex, 1);
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

    Future<void> saveSession(List<String> ids, int index, Duration at) async =>
        storage[PlaybackSessionStore.sessionKey] = jsonEncode(
          PlaybackSessionSnapshot(
            songIds: ids,
            currentIndex: index,
            position: at,
          ).toJson(),
        );

    test('SN-50 #22: after a restart, a queue playing the second copy of a '
        'song resumes that copy where it was', () async {
      await saveSession(['a', 'b', 'a'], 2, const Duration(minutes: 1));

      final (restoredPlayer, restoredEngine) = await restart();
      final state = restoredEngine.currentState;
      expect(state.queue.tracks.map((t) => t.songId), ['a', 'b', 'a']);
      expect(state.queue.currentIndex, 2);
      expect(state.position, const Duration(minutes: 1));

      await PlaybackCoordinator(engine: restoredEngine).play();
      await settle();

      expect(restoredPlayer.audible, isTrue);
      expect(restoredEngine.currentState.queue.currentIndex, 2);
      expect(restoredEngine.currentState.position, const Duration(minutes: 1));
    });

    test('SN-50 #22: a finished queue ending on the second copy replays that '
        'copy after a restart (R4)', () async {
      await saveSession(['a', 'b', 'a'], 2, const Duration(minutes: 3));

      final (restoredPlayer, restoredEngine) = await restart();
      expect(restoredEngine.currentState.queue.currentIndex, 2);

      await PlaybackCoordinator(engine: restoredEngine).play();
      await settle();

      expect(restoredPlayer.audible, isTrue);
      expect(restoredEngine.currentState.queue.currentIndex, 2);
      expect(restoredEngine.currentState.position, Duration.zero);
      expect(restoredEngine.currentState.queue.length, 3);
    });

    test('SN-50 A1: after a restart under Repeat One, Next moves on', () async {
      await saveSession(['a', 'b', 'c'], 0, const Duration(seconds: 30));

      final (_, restoredEngine) = await restart();
      await restoredEngine.setRepeatMode(PlaybackRepeatMode.one);
      await PlaybackCoordinator(engine: restoredEngine).skipNext();
      await settle();

      expect(restoredEngine.currentState.queue.currentIndex, 1);
      expect(restoredEngine.currentState.repeatMode, PlaybackRepeatMode.one);
    });

    test('SN-50 A2: cleared songs do not come back after a restart', () async {
      await saveSession(['a', 'b', 'c'], 1, const Duration(seconds: 30));

      final (_, restoredEngine) = await restart();
      final removed = await PlaybackCoordinator(
        engine: restoredEngine,
      ).clearQueue();
      await settle();
      expect(removed, 2);
      expect(restoredEngine.currentState.queue.tracks.map((t) => t.songId), [
        'b',
      ]);

      final (_, again) = await restart();
      expect(again.currentState.queue.tracks.map((t) => t.songId), ['b']);
      expect(again.currentState.position, const Duration(seconds: 30));
    });

    group('SN-50 #24: the exact shuffled order', () {
      Future<void> saveShuffled(
        List<String> ids,
        int index,
        Object? shuffleOrder,
      ) async {
        final json = PlaybackSessionSnapshot(
          songIds: ids,
          currentIndex: index,
          position: const Duration(seconds: 30),
        ).toJson();
        storage[PlaybackSessionStore.sessionKey] = jsonEncode({
          ...json,
          'shuffleOrder': ?shuffleOrder,
        });
      }

      /// A new process where "Remember shuffle and repeat" turned shuffle
      /// on (or not) before the session is restored, as at launch.
      Future<(SimulatedJustAudioPlayer, JustAudioPlaybackEngine)> launch({
        required bool shuffle,
        List<String> library = const ['a', 'b', 'c', 'd'],
      }) async {
        final nextPlayer = SimulatedJustAudioPlayer(modelShuffle: true);
        final nextEngine = JustAudioPlaybackEngine(
          audioPlayer: nextPlayer,
          configureAudioSession: () async {},
        );
        addTearDown(nextEngine.dispose);
        if (shuffle) await nextEngine.setShuffleEnabled(true);
        final restorer = PlaybackRestorationController(
          store: store(),
          coordinator: PlaybackCoordinator(engine: nextEngine),
        );
        addTearDown(restorer.dispose);
        await restorer.restore(
          () async => [for (final id in library) libraryTrack(id)],
        );
        await settle();
        return (nextPlayer, nextEngine);
      }

      Future<List<String>> nextOrder(
        JustAudioPlaybackEngine engine,
        int steps,
      ) async {
        final coordinator = PlaybackCoordinator(engine: engine);
        final seen = <String>[];
        for (var step = 0; step < steps; step++) {
          await coordinator.skipNext();
          await settle();
          seen.add(engine.currentState.queue.currentTrack!.songId);
        }
        return seen;
      }

      test('with Remember on, Next follows the saved shuffled order', () async {
        await saveShuffled(['a', 'b', 'c', 'd'], 2, [2, 0, 3, 1]);

        final (player, engine) = await launch(shuffle: true);

        expect(player.shuffleIndices, [2, 0, 3, 1]);
        expect(engine.currentState.queue.currentTrack?.songId, 'c');
        expect(engine.currentState.position, const Duration(seconds: 30));
        expect(await nextOrder(engine, 3), ['a', 'd', 'b']);
      });

      test('with Remember off, the queue is restored in queue order as '
          'before', () async {
        await saveShuffled(['a', 'b', 'c', 'd'], 2, [2, 0, 3, 1]);

        final (_, engine) = await launch(shuffle: false);

        expect(engine.currentState.shuffleEnabled, isFalse);
        expect(await nextOrder(engine, 1), ['d']);
      });

      test('a song that is gone is left out; the rest keep their saved '
          'order', () async {
        await saveShuffled(['a', 'b', 'c', 'd'], 2, [2, 0, 3, 1]);

        final (player, engine) = await launch(
          shuffle: true,
          library: ['a', 'c', 'd'],
        );

        expect(engine.currentState.queue.tracks.map((t) => t.songId), [
          'a',
          'c',
          'd',
        ]);
        expect(player.shuffleIndices, [1, 0, 2]);
        expect(await nextOrder(engine, 2), ['a', 'd']);
      });

      test('a song queued twice keeps each copy in its place', () async {
        await saveShuffled(['a', 'b', 'a'], 2, [2, 0, 1]);

        final (player, engine) = await launch(shuffle: true);

        expect(player.shuffleIndices, [2, 0, 1]);
        expect(engine.currentState.queue.currentIndex, 2);
        expect(await nextOrder(engine, 2), ['a', 'b']);
        expect(engine.currentState.queue.currentIndex, 1);
      });

      test('an invalid saved order is dropped; the session still comes '
          'back, freshly shuffled', () async {
        await saveShuffled(['a', 'b', 'c', 'd'], 1, [0, 0, 1, 2]);

        final (player, engine) = await launch(shuffle: true);

        expect(engine.currentState.queue.length, 4);
        expect(engine.currentState.queue.currentTrack?.songId, 'b');
        expect(player.shuffleIndices.toSet(), {0, 1, 2, 3});
      });

      test('the order a session played in is saved, and comes back after '
          'a restart', () async {
        final (firstPlayer, firstEngine) = await launch(shuffle: true);
        await firstEngine.loadQueue([
          for (final id in ['a', 'b', 'c', 'd']) _track(id),
        ], startIndex: 1);
        await settle();
        await firstEngine.seek(const Duration(seconds: 12));
        await settle();
        final played = List.of(firstPlayer.shuffleIndices);

        final saved = PlaybackSessionSnapshot.fromJson(
          jsonDecode(storage[PlaybackSessionStore.sessionKey]!)
              as Map<String, Object?>,
        )!;
        expect(saved.shuffleOrder, played);

        final (secondPlayer, _) = await launch(shuffle: true);
        expect(secondPlayer.shuffleIndices, played);
      });
    });

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

  group('SN-50 reconciliation: playback races (F3, F4, F5)', () {
    test('two quick system Shuffle taps toggle twice, not once (F4)', () async {
      await engine.loadQueue([_track('a'), _track('b')]);
      await settle();
      expect(engine.currentState.shuffleEnabled, isFalse);
      final seen = <bool>[];
      final subscription = engine.states.listen(
        (state) => seen.add(state.shuffleEnabled),
      );
      addTearDown(subscription.cancel);

      await Future.wait([
        handler.customAction(MediaSessionStateMapper.shuffleAction),
        handler.customAction(MediaSessionStateMapper.shuffleAction),
      ]);
      await settle();

      expect(seen, contains(isTrue), reason: 'the first tap turned it on');
      expect(engine.currentState.shuffleEnabled, isFalse);
    });

    test(
      'three quick system Repeat taps cycle Off, All, One, Off (F4)',
      () async {
        await engine.loadQueue([_track('a')]);
        await settle();
        final modes = <PlaybackRepeatMode>[];
        final subscription = engine.states.listen(
          (state) => modes.add(state.repeatMode),
        );
        addTearDown(subscription.cancel);

        await Future.wait([
          for (var tap = 0; tap < 3; tap++)
            handler.customAction(MediaSessionStateMapper.repeatAction),
        ]);
        await settle();

        expect(modes.toSet(), containsAll(PlaybackRepeatMode.values));
        expect(engine.currentState.repeatMode, PlaybackRepeatMode.off);
      },
    );

    test('a pause in the last second of the last song, then Play, resumes '
        'there instead of replaying it (F5)', () async {
      await engine.loadQueue([_track('a'), _track('b')], startIndex: 1);
      await settle();
      await coordinator.play();
      await settle();
      player.advanceTo(
        const Duration(minutes: 2, seconds: 59, milliseconds: 400),
      );
      await settle();
      await coordinator.pause();
      await settle();
      final positions = <Duration>[];
      final subscription = engine.states.listen(
        (state) => positions.add(state.position),
      );
      addTearDown(subscription.cancel);

      await coordinator.play();
      await settle();

      expect(player.audible, isTrue);
      expect(positions, isNot(contains(Duration.zero)));
      expect(
        engine.currentState.position,
        const Duration(minutes: 2, seconds: 59, milliseconds: 400),
      );
      expect(engine.currentState.queue.currentTrack?.songId, 'b');
    });

    test('paused at a position set in the last second, as a restore does, '
        'Play still replays from 0:00 (R4 kept)', () async {
      await engine.loadQueue([_track('a'), _track('b')], startIndex: 1);
      await settle();
      await engine.seek(
        const Duration(minutes: 2, seconds: 59, milliseconds: 600),
      );
      await settle();

      await coordinator.play();
      await settle();

      expect(player.audible, isTrue);
      expect(engine.currentState.position, Duration.zero);
      expect(engine.currentState.queue.currentTrack?.songId, 'b');
    });

    for (final (name, edit) in <(String, Future<void> Function())>[
      ('an insert', () => engine.insertTrack(_track('c'), index: 1)),
      ('a removal', () => engine.removeTrackAt(1)),
      ('a move', () => engine.moveTrack(oldIndex: 0, newIndex: 1)),
    ]) {
      test('a credit refresh that lands during $name is kept (F3)', () async {
        await engine.loadQueue([_track('a'), _track('b')]);
        await settle();

        final editing = edit();
        final refreshed = engine.refreshTrackDisplay([
          _track('a').copyWith(
            displayTitle: 'Song a (Live)',
            displayArtist: 'Artist Ft. Guest',
          ),
        ]);
        await editing;
        await settle();

        expect(refreshed, isTrue);
        final a = engine.currentState.queue.tracks.singleWhere(
          (track) => track.songId == 'a',
        );
        expect(a.displayTitle, 'Song a (Live)');
        expect(a.displayArtist, 'Artist Ft. Guest');
        expect(a.title, 'Song a', reason: 'history keeps the stored title');
      });
    }
  });
}
