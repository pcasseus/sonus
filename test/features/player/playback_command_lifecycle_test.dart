// App Update 1.2, BUG-11: Shuffle, Repeat, Next, Previous and queue edits
// work at once however playback was started.
//
// just_audio's play() Future completes only when playback later pauses,
// stops or reaches the end of the queue, never when it starts. The engine
// awaited it inside its command queue (BUG-05), so after a queue was loaded
// with autoplay every later command waited for the whole song. These tests
// drive the real engine, coordinator and media session handler over a
// simulated player whose play() stays pending while playback goes on, as
// the real one does. A command that waits behind playback fails its
// [_soon] deadline instead of hanging the suite.

import 'dart:async';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_state_mapper.dart';
import 'package:sonus_next/features/player/application/services/media_session/sonus_audio_handler.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';

import 'data/engines/simulated_just_audio_player.dart';

/// A command that is not waiting behind playback finishes well within this.
Future<T> _soon<T>(Future<T> command) =>
    command.timeout(const Duration(seconds: 2));

Future<void> _settle() => Future<void>.delayed(Duration.zero);

LibraryTrack _song(String id) => LibraryTrack(
  songId: id,
  title: id,
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  albumEditionId: 'edition',
  albumEditionTitle: 'Album',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime.utc(2026, 9, 11),
  isAvailable: true,
  filePath: '/music/$id.mp3',
);

PlaybackTrack _track(String id) => PlaybackTrack(
  songId: id,
  title: id,
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
);

final _album = [
  for (final id in ['a', 'b', 'c', 'd', 'e']) _song(id),
];

/// A player whose play request fails after it was made, as one does when
/// the audio session or the platform refuses to start.
class _FailingStart extends SimulatedJustAudioPlayer {
  @override
  Future<void> play() {
    super.play();
    return Future<void>.error(StateError('platform refused to play'));
  }
}

void main() {
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;

  setUp(() {
    player = SimulatedJustAudioPlayer(modelShuffle: true);
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
  });

  tearDown(() => engine.dispose());

  PlaybackState state() => engine.currentState;
  String? current() => state().queue.currentTrack?.songId;

  /// Every mode and queue command completes promptly, and the song that
  /// was playing keeps playing with the same identity.
  Future<void> expectCommandsWork() async {
    final playing = current();
    expect(playing, isNotNull);

    await _soon(coordinator.setShuffleEnabled(true));
    expect(state().shuffleEnabled, isTrue);
    expect(current(), playing, reason: 'shuffle keeps the current song');

    for (final mode in [
      PlaybackRepeatMode.all,
      PlaybackRepeatMode.one,
      PlaybackRepeatMode.off,
    ]) {
      await _soon(coordinator.setRepeatMode(mode));
      expect(state().repeatMode, mode);
      expect(current(), playing);
    }

    await _soon(coordinator.setShuffleEnabled(false));
    expect(state().shuffleEnabled, isFalse);
    expect(current(), playing);
    expect(player.audible, isTrue, reason: 'playback went on throughout');
  }

  group('playback that has started never blocks the next command', () {
    test('the deadlock itself: a play request is still pending while the '
        'queue plays', () async {
      await _soon(coordinator.playTracks(_album));
      expect(player.playRequestPending, isTrue);
      expect(state().status, PlaybackStatus.playing);
      await expectCommandsWork();
    });

    test('Album Play / Play all (playTracks from the first song)', () async {
      await _soon(coordinator.playTracks(_album));
      expect(current(), 'a');
      await expectCommandsWork();
    });

    test('Album Shuffle / Shuffle all (shuffle on, then playTracks)', () async {
      await _soon(coordinator.setShuffleEnabled(true));
      await _soon(coordinator.playTracks(_album, startIndex: 3));
      expect(current(), 'd');
      expect(state().shuffleEnabled, isTrue);
      await _soon(coordinator.setRepeatMode(PlaybackRepeatMode.all));
      await _soon(coordinator.setShuffleEnabled(false));
      expect(current(), 'd');
    });

    test('an individual track tap (playTrack)', () async {
      await _soon(coordinator.playTrack(_song('x')));
      expect(current(), 'x');
      await expectCommandsWork();
    });

    test('Search, Artist and chart lists (playInContext)', () async {
      await _soon(coordinator.playInContext(_album[2], _album));
      expect(current(), 'c');
      await expectCommandsWork();
    });

    test(
      'a restored or saved shuffle order (loadQueueInShuffleOrder)',
      () async {
        await _soon(coordinator.setShuffleEnabled(true));
        await _soon(
          coordinator.playTracks(
            _album,
            startIndex: 1,
            shuffleOrder: const [1, 4, 0, 3, 2],
          ),
        );
        expect(current(), 'b');
        await expectCommandsWork();
      },
    );

    test('Play Next and Add to Queue on an idle player', () async {
      await _soon(coordinator.addToQueue(_song('q1')));
      await _soon(coordinator.playNext(_song('q2')));
      expect(state().queue.length, greaterThan(0));
      await _soon(coordinator.play());
      await expectCommandsWork();
    });

    test('resume after pause, then resume again', () async {
      await _soon(coordinator.playTracks(_album));
      await _soon(coordinator.pause());
      expect(player.playRequestPending, isFalse);
      await _soon(coordinator.togglePlayPause());
      expect(player.playRequestPending, isTrue);
      expect(player.audible, isTrue);
      await expectCommandsWork();
    });

    test('switching albums mid-playback', () async {
      await _soon(coordinator.playTracks(_album));
      await _soon(coordinator.playTracks([_song('p'), _song('q'), _song('r')]));
      expect(current(), 'p');
      await expectCommandsWork();
    });

    test('Play after the queue finished replays the last song and does '
        'not block', () async {
      await _soon(coordinator.playTracks([_song('only')]));
      player.complete();
      await _settle();
      expect(state().status, PlaybackStatus.completed);

      await _soon(coordinator.play());
      expect(player.audible, isTrue);
      await expectCommandsWork();
    });
  });

  group('Next, Previous and queue edits while playing', () {
    setUp(() async {
      await _soon(coordinator.playTracks(_album));
    });

    test('Next, Previous and a chosen queue item', () async {
      await _soon(coordinator.skipNext());
      expect(current(), 'b');
      await _soon(coordinator.skipPrevious());
      expect(current(), 'a');
      await _soon(coordinator.skipToIndex(3));
      expect(current(), 'd');
      expect(player.audible, isTrue);
    });

    test(
      'append, insert next, move and remove keep the playing song',
      () async {
        await _soon(coordinator.addToQueue(_song('z')));
        await _soon(coordinator.playNext(_song('n')));
        await _soon(coordinator.moveQueueTrack(oldIndex: 4, newIndex: 2));
        await _soon(coordinator.removeFromQueue(3));
        expect(current(), 'a');
        expect(
          [for (final t in state().queue.tracks) t.songId],
          ['a', 'n', 'd', 'c', 'e', 'z'],
        );
      },
    );

    test('commands issued together still run in order (BUG-05)', () async {
      await _soon(
        Future.wait([
          coordinator.addToQueue(_song('x1')),
          coordinator.setShuffleEnabled(true),
          coordinator.addToQueue(_song('x2')),
          coordinator.setRepeatMode(PlaybackRepeatMode.all),
          coordinator.addToQueue(_song('x3')),
          coordinator.setShuffleEnabled(false),
        ]),
      );
      final ids = [for (final t in state().queue.tracks) t.songId];
      expect(ids.sublist(ids.length - 3), ['x1', 'x2', 'x3']);
      expect(ids.length, player.sourceCountForTest);
      expect(state().shuffleEnabled, isFalse);
      expect(state().repeatMode, PlaybackRepeatMode.all);
      expect(current(), 'a');
    });

    test('rapid repeated taps settle on the last one', () async {
      await _soon(
        Future.wait([
          for (var i = 0; i < 7; i++) coordinator.setShuffleEnabled(i.isEven),
          for (final mode in [
            PlaybackRepeatMode.all,
            PlaybackRepeatMode.one,
            PlaybackRepeatMode.off,
            PlaybackRepeatMode.all,
          ])
            coordinator.setRepeatMode(mode),
        ]),
      );
      expect(state().shuffleEnabled, isTrue);
      expect(state().repeatMode, PlaybackRepeatMode.all);
      expect(current(), 'a');
    });

    test('modes change while a song change is in flight', () async {
      final skip = coordinator.skipNext();
      final shuffle = coordinator.setShuffleEnabled(true);
      final repeat = coordinator.setRepeatMode(PlaybackRepeatMode.one);
      await _soon(Future.wait([skip, shuffle, repeat]));
      expect(current(), 'b');
      expect(state().shuffleEnabled, isTrue);
      expect(state().repeatMode, PlaybackRepeatMode.one);
    });

    test('modes change while paused, and playback resumes as left', () async {
      await _soon(coordinator.pause());
      await _soon(coordinator.setShuffleEnabled(true));
      await _soon(coordinator.setRepeatMode(PlaybackRepeatMode.one));
      expect(player.audible, isFalse);
      await _soon(coordinator.play());
      expect(player.audible, isTrue);
      expect(current(), 'a');
    });
  });

  group('one, two or many entries, and duplicates', () {
    test('a single song: every mode and Next/Previous respond', () async {
      await _soon(coordinator.playTracks([_song('solo')]));
      await expectCommandsWork();
      await _soon(coordinator.skipNext());
      await _soon(coordinator.skipPrevious());
      expect(current(), 'solo');
    });

    test('the same song twice: Next goes to its second copy', () async {
      await _soon(coordinator.playTracks([_song('a'), _song('a')]));
      expect(state().queue.currentIndex, 0);
      await _soon(coordinator.skipNext());
      expect(state().queue.currentIndex, 1);
      expect(current(), 'a');
      await expectCommandsWork();
    });
  });

  group('a playback start that fails', () {
    test('is reported as a failure, with no unhandled error, and the next '
        'command still runs', () async {
      final failing = _FailingStart();
      final failingEngine = JustAudioPlaybackEngine(
        audioPlayer: failing,
        configureAudioSession: () async {},
      );
      addTearDown(failingEngine.dispose);

      await _soon(failingEngine.loadQueue([_track('a')], autoPlay: true));
      await _settle();
      expect(failingEngine.currentState.status, PlaybackStatus.failed);

      await _soon(failingEngine.setRepeatMode(PlaybackRepeatMode.all));
      expect(failingEngine.currentState.repeatMode, PlaybackRepeatMode.all);
    });

    test('Play (resume) that fails reports it, without throwing', () async {
      final failing = _FailingStart();
      final failingEngine = JustAudioPlaybackEngine(
        audioPlayer: failing,
        configureAudioSession: () async {},
      );
      addTearDown(failingEngine.dispose);
      await _soon(failingEngine.loadQueue([_track('a')]));

      await _soon(failingEngine.play());
      await _settle();
      expect(failingEngine.currentState.status, PlaybackStatus.failed);
    });

    test('a failure after disposal is ignored', () async {
      final failing = _FailingStart();
      final failingEngine = JustAudioPlaybackEngine(
        audioPlayer: failing,
        configureAudioSession: () async {},
      );
      await _soon(failingEngine.loadQueue([_track('a')], autoPlay: true));
      await failingEngine.dispose();
      await _settle();
    });
  });

  group('the system player (notification, lock screen, Android Auto)', () {
    late SonusAudioHandler handler;

    setUp(() {
      handler = SonusAudioHandler(
        artworkExists: (_) => true,
        log: (message, {level = 800}) {},
      )..attach(coordinator);
    });

    test('Shuffle and Repeat apply while playing', () async {
      await _soon(coordinator.playTracks(_album));

      await _soon(handler.customAction(MediaSessionStateMapper.shuffleAction));
      expect(state().shuffleEnabled, isTrue);
      await _soon(handler.customAction(MediaSessionStateMapper.repeatAction));
      expect(state().repeatMode, PlaybackRepeatMode.all);
      await _soon(handler.setShuffleMode(media.AudioServiceShuffleMode.none));
      await _soon(handler.setRepeatMode(media.AudioServiceRepeatMode.one));
      expect(state().shuffleEnabled, isFalse);
      expect(state().repeatMode, PlaybackRepeatMode.one);
      expect(current(), 'a');
    });

    test('Play, then Next, Previous and a queue item respond', () async {
      await _soon(coordinator.playTracks(_album, autoPlay: false));
      await _soon(handler.play());
      expect(player.audible, isTrue);
      await _soon(handler.skipToNext());
      expect(current(), 'b');
      await _soon(handler.skipToPrevious());
      await _soon(handler.skipToQueueItem(4));
      expect(current(), 'e');
    });

    test('Play during a saved session that restores slowly is applied once '
        'the session is back', () async {
      final restore = Completer<void>();
      final slow = SonusAudioHandler(
        log: (message, {level = 800}) {},
        readinessTimeout: const Duration(milliseconds: 20),
      )..attach(coordinator, restored: restore.future);

      await _soon(slow.play()); // times out: nothing is queued yet
      expect(player.audible, isFalse);

      // The restore loads the saved queue paused, as it always does.
      await _soon(coordinator.playTracks(_album, autoPlay: false));
      restore.complete();
      await _settle();
      await _settle();

      expect(player.audible, isTrue, reason: 'the Play was kept');
      expect(current(), 'a');
    });

    test('a Pause after that Play wins', () async {
      final restore = Completer<void>();
      final slow = SonusAudioHandler(
        log: (message, {level = 800}) {},
        readinessTimeout: const Duration(milliseconds: 20),
      )..attach(coordinator, restored: restore.future);

      await _soon(slow.play());
      await _soon(slow.pause());
      await _soon(coordinator.playTracks(_album, autoPlay: false));
      restore.complete();
      await _settle();
      await _settle();

      expect(player.audible, isFalse);
    });
  });

  group('saved-session restore and the listener act at the same time', () {
    test("the listener's song plays from its start, not the restored "
        'position', () async {
      // PlaybackRestorationController: load the saved queue paused, then
      // seek to the saved position. The listener taps a song meanwhile.
      final restore = () async {
        await coordinator.playTracks(
          [_song('saved1'), _song('saved2')],
          startIndex: 1,
          autoPlay: false,
        );
        await coordinator.seek(const Duration(minutes: 2));
      }();
      final tap = coordinator.playTracks(_album, startIndex: 2);
      await _soon(Future.wait([restore, tap]));
      await _settle();

      expect(current(), 'c');
      expect(state().position, Duration.zero);
      expect(player.audible, isTrue);
    });
  });

  group('the player goes away while commands wait', () {
    test(
      'commands queued before disposal are dropped without errors',
      () async {
        final local = SimulatedJustAudioPlayer();
        final localEngine = JustAudioPlaybackEngine(
          audioPlayer: local,
          configureAudioSession: () async {},
        );
        final errors = <Object>[];

        await runZonedGuarded(() async {
          // A command in flight holds the turn while the others queue.
          final load = localEngine.loadQueue([_track('a'), _track('b')]);
          final queued = [
            localEngine.setShuffleEnabled(true),
            localEngine.skipNext(),
            localEngine.appendTrack(_track('c')),
          ];
          await localEngine.dispose();
          await load.catchError((Object _) {});
          await _soon(Future.wait(queued));
        }, (error, _) => errors.add(error));
        await _settle();

        expect(errors, isEmpty);
      },
    );

    test('a command issued after disposal still fails', () async {
      final localEngine = JustAudioPlaybackEngine(
        audioPlayer: SimulatedJustAudioPlayer(),
        configureAudioSession: () async {},
      );
      await localEngine.dispose();

      await expectLater(localEngine.skipNext(), throwsStateError);
    });
  });
}
