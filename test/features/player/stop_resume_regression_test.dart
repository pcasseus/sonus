// SN-44 device QA: Stop then Play resumed audio from the stopped position,
// but Sonus reported position and duration 0. Now Playing showed 0:00 with
// no progress and a disabled seek bar, and a later restart restored 0:00.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_playback_progress.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_restoration_controller.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/data/services/playback_session_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/player/presentation/pages/now_playing_page.dart';

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

LibraryTrack _libraryTrack(String id) => LibraryTrack(
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

void main() {
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;

  setUp(() {
    player = SimulatedJustAudioPlayer();
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
  });

  tearDown(() => engine.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Plays song a to 1:14, then stops.
  Future<void> playThenStop() async {
    await engine.loadQueue([_track('a'), _track('b')], autoPlay: true);
    await settle();
    player.advanceTo(const Duration(seconds: 74));
    await settle();
    await coordinator.stop();
    await settle();
  }

  group('Stop keeps what the player keeps', () {
    test(
      'stopping reports idle with the retained position and duration',
      () async {
        await playThenStop();

        expect(engine.currentState.status, PlaybackStatus.idle);
        expect(engine.currentState.position, const Duration(seconds: 74));
        expect(engine.currentState.duration, const Duration(minutes: 3));
        expect(engine.currentState.queue.currentTrack?.songId, 'a');
        expect(player.audible, isFalse);
      },
    );

    test(
      'Play after Stop resumes with position, duration and progress',
      () async {
        await playThenStop();

        await coordinator.play();
        await settle();

        expect(player.audible, isTrue);
        expect(engine.currentState.status, PlaybackStatus.playing);
        expect(engine.currentState.position, const Duration(seconds: 74));
        expect(engine.currentState.duration, const Duration(minutes: 3));
        expect(engine.currentState.progress, closeTo(74 / 180, 0.001));

        player.advanceTo(const Duration(seconds: 80));
        await settle();
        expect(engine.currentState.position, const Duration(seconds: 80));
      },
    );

    test('Stop never starts audio by itself', () async {
      await playThenStop();
      await settle();

      expect(player.audible, isFalse);
      expect(engine.currentState.isPlaying, isFalse);
    });
  });

  testWidgets(
    'Now Playing shows progress and allows seeking after Stop then Play',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stateController = PlaybackStateController(coordinator: coordinator);
      addTearDown(stateController.dispose);

      await tester.runAsync(playThenStop);
      await tester.runAsync(() async {
        await coordinator.play();
        await settle();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PlaybackCoordinator>.value(value: coordinator),
            ChangeNotifierProvider<PlaybackStateController>.value(
              value: stateController,
            ),
            ChangeNotifierProvider<LyricsController?>.value(value: null),
          ],
          child: const MaterialApp(home: NowPlayingPage()),
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('now-playing-elapsed')),
            )
            .data,
        '1:14',
      );
      final progress = tester.widget<SonusPlaybackProgress>(
        find.byKey(const ValueKey<String>('now-playing-seek')),
      );
      expect(progress.position.inMilliseconds, closeTo(74000, 1));
      expect(progress.duration, const Duration(minutes: 3));
      expect(progress.onSeek, isNotNull, reason: 'seeking must stay available');
    },
  );

  test('closing after Stop restores the stopped position, paused', () async {
    final storage = <String, String>{};
    PlaybackSessionStore store() => PlaybackSessionStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
      remove: (key) async => storage.remove(key),
    );

    final recorder = PlaybackRestorationController(
      store: store(),
      coordinator: coordinator,
    );
    await recorder.restore(() async => const []);
    await playThenStop();
    await recorder.saveNow();
    recorder.dispose();

    // A new process: fresh engine and coordinator, same stored session.
    final nextPlayer = SimulatedJustAudioPlayer();
    final nextEngine = JustAudioPlaybackEngine(
      audioPlayer: nextPlayer,
      configureAudioSession: () async {},
    );
    addTearDown(nextEngine.dispose);
    final nextCoordinator = PlaybackCoordinator(engine: nextEngine);
    final restorer = PlaybackRestorationController(
      store: store(),
      coordinator: nextCoordinator,
    );
    addTearDown(restorer.dispose);

    await restorer.restore(
      () async => [
        for (final id in ['a', 'b']) _libraryTrack(id),
      ],
    );
    await settle();

    expect(nextEngine.currentState.queue.currentTrack?.songId, 'a');
    expect(nextEngine.currentState.position, const Duration(seconds: 74));
    expect(nextEngine.currentState.isPlaying, isFalse);
    expect(nextPlayer.audible, isFalse);
  });

  test(
    'Stop still ends the media session and releases the notification',
    () async {
      var releases = 0;
      final handler = SonusAudioHandler(
        artworkExists: (_) => false,
        releaseForeground: () async => releases++,
      )..attach(coordinator);
      addTearDown(() => handler.detach(coordinator));

      await engine.loadQueue([_track('a')], autoPlay: true);
      await settle();
      player.advanceTo(const Duration(seconds: 74));
      await settle();

      await handler.stop();
      await settle();

      expect(releases, 1);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.mediaItem.value, isNull);
    },
  );
}
