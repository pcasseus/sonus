// SN-50 device QA: with Shuffle on, Sonus played a song that had already
// played. Traced to the shuffle order: turning shuffle on mid-queue
// reshuffled every entry (played ones too), a jump to a chosen entry
// played on from its place in the shuffled order (replaying what came
// after it), and a moved entry was placed anywhere. These drive the real
// engine over just_audio's modelled play order.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/data/engines/support/sonus_shuffle_order.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
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

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;

  setUp(() {
    player = SimulatedJustAudioPlayer(modelShuffle: true);
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
  });

  tearDown(() => engine.dispose());

  int current() => engine.currentState.queue.currentIndex;

  Future<List<int>> playOn(int steps) async {
    final seen = <int>[];
    for (var i = 0; i < steps; i++) {
      await engine.skipNext();
      await _settle();
      seen.add(current());
    }
    return seen;
  }

  Set<int> played() => playedQueueIndices(
    length: engine.currentState.queue.length,
    currentIndex: current(),
    shuffleOrder: engine.shuffleOrder,
  );

  Future<void> load(int count, {int start = 0}) async {
    await engine.loadQueue([
      for (var i = 0; i < count; i++) _track('s$i'),
    ], startIndex: start);
    await _settle();
  }

  test(
    'turning shuffle on mid-queue never replays what already played',
    () async {
      await load(10);
      await playOn(3); // s0..s3 heard in order
      expect(current(), 3);

      await engine.setShuffleEnabled(true);
      await _settle();
      expect(played(), {0, 1, 2});

      final rest = await playOn(6);
      expect(rest.toSet(), {4, 5, 6, 7, 8, 9});
      expect(rest.toSet().intersection({0, 1, 2, 3}), isEmpty);
    },
  );

  test('a full shuffled cycle plays every entry once', () async {
    await engine.setShuffleEnabled(true);
    await load(8);
    final heard = [current(), ...await playOn(7)];
    expect(heard.toSet(), hasLength(8));
  });

  test('a song queued twice plays twice, each entry once', () async {
    await engine.setShuffleEnabled(true);
    await engine.loadQueue([
      _track('a'),
      _track('b'),
      _track('a'),
      _track('c'),
    ]);
    await _settle();
    final heard = [current(), ...await playOn(3)];
    expect(heard.toSet(), {0, 1, 2, 3});
  });

  test('choosing a played entry replays it, then the cycle continues '
      'without other repeats', () async {
    await engine.setShuffleEnabled(true);
    await load(8);
    final first = [current(), ...await playOn(3)];
    final chosen = first.first;

    await engine.skipToIndex(chosen);
    await _settle();
    expect(current(), chosen);
    expect(played(), containsAll(first.where((i) => i != chosen)));

    final rest = await playOn(4);
    expect(rest.toSet().intersection(first.toSet()), isEmpty);
    expect({...first, ...rest}, hasLength(8));
  });

  test('choosing an upcoming entry skips none of the others', () async {
    await engine.setShuffleEnabled(true);
    await load(8);
    final upcoming = engine.shuffleOrder!.last;
    await engine.skipToIndex(upcoming);
    await _settle();
    final rest = await playOn(6);
    expect({current(), ...rest, upcoming}.length, greaterThanOrEqualTo(7));
    expect(rest.toSet(), hasLength(6));
  });

  test('Previous goes back through the played entries', () async {
    await engine.setShuffleEnabled(true);
    await load(6);
    final heard = [current(), ...await playOn(2)];
    await engine.skipPrevious();
    await _settle();
    expect(current(), heard[1]);
  });

  test(
    'Repeat All starts a new cycle; Repeat One repeats on its own',
    () async {
      await engine.setShuffleEnabled(true);
      await engine.setRepeatMode(PlaybackRepeatMode.all);
      await load(4);
      final cycle = [current(), ...await playOn(3)];
      expect(cycle.toSet(), hasLength(4));
      final next = await playOn(1);
      expect(next.single, cycle.first, reason: 'the cycle starts again');
      expect(played(), isEmpty);
    },
  );

  test('moving a played entry keeps it played', () async {
    await engine.setShuffleEnabled(true);
    await load(6);
    await playOn(2);
    final before = played();
    final moved = before.first;
    final target = moved == 5 ? 4 : 5;
    await engine.moveTrack(oldIndex: moved, newIndex: target);
    await _settle();
    final afterMove = played();
    expect(afterMove, hasLength(before.length));
    final rest = await playOn(3);
    expect(rest.toSet().intersection(afterMove), isEmpty);
  });

  test('a saved shuffle order is restored exactly', () async {
    await engine.setShuffleEnabled(true);
    await engine.loadQueueInShuffleOrder(
      [for (var i = 0; i < 4; i++) _track('s$i')],
      shuffleOrder: const [2, 0, 3, 1],
      startIndex: 0,
    );
    await _settle();
    expect(engine.shuffleOrder, [2, 0, 3, 1]);
    expect(played(), {2});
  });
}
