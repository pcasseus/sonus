// SN-50 Session D: the system player's Shuffle and Repeat, and the end of
// the queue, through the real engine (with a simulated just_audio player),
// the coordinator and the media session.
import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_preferences_controller.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_state_mapper.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/data/services/playback_preferences_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
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

    test('Play after the end does nothing yet (open decision M-1)', () async {
      await playToTheEnd();
      statuses.clear();

      await handler.play();
      await coordinator.togglePlayPause();
      await settle();

      expect(player.audible, isFalse);
      expect(engine.currentState.status, PlaybackStatus.completed);
      expect(statuses, isNot(contains(PlaybackStatus.playing)));
    });
  });
}
