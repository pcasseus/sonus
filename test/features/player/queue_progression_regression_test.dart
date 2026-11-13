// App Update 1.2 patches, Checkpoint 2 (BUG-05, BUG-06): the engine's queue
// and the player's sources never drift apart, so playback keeps advancing
// through every remaining entry and the playing song keeps its identity.
// These drive the real engine over the simulated just_audio player.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/models/playback_transition_cause.dart';

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

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A player whose current song ends while a queue change is in flight:
/// the player moves on to [endsInto] before the change returns, as
/// just_audio does when a song finishes during an insert.
class _AdvancesDuringInsert extends SimulatedJustAudioPlayer {
  _AdvancesDuringInsert({super.modelShuffle});

  int? endsInto;
  int sources = 0;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    this.sources = sources.length;
    return super.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async {
    await super.insertAudioSource(index, source);
    sources++;
    final target = endsInto;
    if (target != null) {
      endsInto = null;
      await seek(Duration.zero, index: target);
    }
    await _settle();
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    await super.removeAudioSourceAt(index);
    sources--;
  }
}

void main() {
  late _AdvancesDuringInsert player;
  late JustAudioPlaybackEngine engine;

  setUp(() {
    player = _AdvancesDuringInsert();
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
  });

  tearDown(() => engine.dispose());

  List<String> queued() => [
    for (final track in engine.currentState.queue.tracks) track.songId,
  ];
  String? playing() => engine.currentState.queue.currentTrack?.songId;

  group('BUG-05: queue progression', () {
    test('songs added at the same time all reach the queue, in order, and '
        'the player has exactly those sources', () async {
      await engine.loadQueue([_track('a1')], autoPlay: true);
      await _settle();

      // "Add to queue" tapped for several songs without waiting, as the
      // song menus do.
      await Future.wait([
        engine.appendTrack(_track('b1')),
        engine.appendTrack(_track('b2')),
        engine.appendTrack(_track('b3')),
        engine.insertTrack(_track('next'), index: 1),
      ]);
      await _settle();

      expect(queued(), ['a1', 'next', 'b1', 'b2', 'b3']);
      expect(player.sources, engine.currentState.queue.length);
      expect(playing(), 'a1');
    });

    test('every remaining song plays in order after an album is added '
        'song by song', () async {
      await engine.loadQueue([_track('a1')], autoPlay: true);
      await _settle();
      await Future.wait([
        for (final id in ['t1', 't2', 't3', 't4'])
          engine.appendTrack(_track(id)),
      ]);
      await _settle();

      final heard = <String?>[playing()];
      for (var i = 1; i < 5; i++) {
        // The song ends and the player moves on by itself.
        await player.seek(Duration.zero, index: i);
        await _settle();
        heard.add(playing());
      }
      expect(heard, ['a1', 't1', 't2', 't3', 't4']);
      expect(engine.currentState.status, PlaybackStatus.playing);
    });

    test('a song that ends while the next one is being added still moves '
        'the queue on', () async {
      await engine.loadQueue(
        [_track('s1'), _track('s2')],
        startIndex: 1,
        autoPlay: true,
      );
      await _settle();
      final transitions = <PlaybackTransitionCause>[];
      final sub = engine.states.listen((state) {
        final cause = state.transitionCause;
        if (cause != null) transitions.add(cause);
      });

      // s2 finishes exactly as s3 is appended: the player starts s3.
      player.endsInto = 2;
      await engine.appendTrack(_track('s3'));
      await _settle();

      expect(queued(), ['s1', 's2', 's3']);
      expect(playing(), 's3', reason: 'the queue follows the player');
      expect(transitions, [PlaybackTransitionCause.automatic]);
      await sub.cancel();
    });

    test('moving an entry across the playing song never reports a song '
        'change', () async {
      await engine.loadQueue(
        [_track('s1'), _track('s2'), _track('s3')],
        startIndex: 1,
        autoPlay: true,
      );
      await _settle();
      final seen = <String?>[];
      final causes = <PlaybackTransitionCause>[];
      final sub = engine.states.listen((state) {
        seen.add(state.queue.currentTrack?.songId);
        final cause = state.transitionCause;
        if (cause != null) causes.add(cause);
      });

      await engine.moveTrack(oldIndex: 0, newIndex: 2);
      await _settle();
      await engine.moveTrack(oldIndex: 2, newIndex: 0);
      await _settle();

      expect(seen.toSet(), {'s2'}, reason: 'only the playing song, s2');
      expect(causes, isEmpty);
      expect(queued(), ['s1', 's2', 's3']);
      await sub.cancel();
    });

    test('Play after a finished queue continues with songs added since, '
        'instead of replaying the finished one', () async {
      await engine.loadQueue([_track('last')], autoPlay: true);
      await _settle();
      player.complete();
      await _settle();
      expect(engine.currentState.status, PlaybackStatus.completed);

      await engine.appendTrack(_track('added'));
      await _settle();
      expect(engine.currentState.nextAvailable, isTrue);

      await engine.play();
      await _settle();

      expect(playing(), 'added');
      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.status, PlaybackStatus.playing);
      expect(player.audible, isTrue);
    });

    test('Play after a finished queue with nothing added still replays the '
        'final song (SN50-R4)', () async {
      await engine.loadQueue([_track('a'), _track('last')], autoPlay: true);
      await _settle();
      await player.seek(Duration.zero, index: 1);
      player.complete();
      await _settle();

      await engine.play();
      await _settle();

      expect(playing(), 'last');
      expect(engine.currentState.status, PlaybackStatus.playing);
    });
  });

  group('BUG-06: shuffle', () {
    setUp(() async {
      await engine.dispose();
      player = _AdvancesDuringInsert(modelShuffle: true);
      engine = JustAudioPlaybackEngine(
        audioPlayer: player,
        configureAudioSession: () async {},
      );
    });

    test('turning shuffle on again while it is on keeps the cycle', () async {
      await engine.loadQueue([
        for (var i = 0; i < 8; i++) _track('s$i'),
      ], autoPlay: true);
      await _settle();
      await engine.setShuffleEnabled(true);
      await engine.skipNext();
      await engine.skipNext();
      await _settle();
      final order = engine.shuffleOrder;
      final current = engine.currentState.queue.currentIndex;

      // A second "shuffle on" (another screen, the notification, a
      // restored preference) must not deal the played songs back in.
      await engine.setShuffleEnabled(true);
      await _settle();

      expect(engine.shuffleOrder, order);
      expect(engine.currentState.queue.currentIndex, current);
    });

    test('songs added at the same time while shuffled are each played once '
        'in the cycle', () async {
      await engine.loadQueue([
        for (var i = 0; i < 4; i++) _track('s$i'),
      ], autoPlay: true);
      await _settle();
      await engine.setShuffleEnabled(true);
      await _settle();
      await Future.wait([
        for (var i = 0; i < 4; i++) engine.appendTrack(_track('added$i')),
      ]);
      await _settle();

      final order = engine.shuffleOrder!;
      expect(order.toSet(), {for (var i = 0; i < 8; i++) i});
      expect(order.first, engine.currentState.queue.currentIndex);

      final heard = <String?>[playing()];
      while (engine.currentState.nextAvailable == true) {
        await engine.skipNext();
        await _settle();
        heard.add(playing());
      }
      expect(heard, hasLength(8));
      expect(heard.toSet(), hasLength(8), reason: 'no song twice');
    });

    test('removing entries while shuffled keeps the playing song and plays '
        'every other remaining entry once', () async {
      // Shuffle turned on at the first song: nothing has played yet.
      await engine.loadQueue([
        for (var i = 0; i < 6; i++) _track('s$i'),
      ], autoPlay: true);
      await _settle();
      await engine.setShuffleEnabled(true);
      await engine.setRepeatMode(PlaybackRepeatMode.off);
      await _settle();

      // Two removals issued together, both numbered from the same queue.
      await Future.wait([engine.removeTrackAt(5), engine.removeTrackAt(3)]);
      await _settle();

      expect(playing(), 's0');
      expect(queued(), ['s0', 's1', 's2', 's4']);
      expect(engine.shuffleOrder!.toSet(), {0, 1, 2, 3});
      final heard = <String?>[playing()];
      while (engine.currentState.nextAvailable == true) {
        await engine.skipNext();
        await _settle();
        heard.add(playing());
      }
      expect(heard.toSet(), {'s0', 's1', 's2', 's4'});
      expect(heard, hasLength(4));
    });
  });
}
