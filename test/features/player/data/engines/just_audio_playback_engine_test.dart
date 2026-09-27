import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/data/engines/support/playback_audio_player.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/models/playback_transition_cause.dart';

class FakePlaybackAudioPlayer implements PlaybackAudioPlayer {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durations =
      StreamController<Duration?>.broadcast();
  final StreamController<int?> _indexes = StreamController<int?>.broadcast();
  final StreamController<PlayerState> _playerStates =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerException> _errors =
      StreamController<PlayerException>.broadcast();

  final List<int> removedIndexes = [];

  int? indexToEmitDuringRemoval;

  bool hasPreviousValue = false;
  bool hasNextValue = false;

  int? currentIndex;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<int?> get currentIndexStream => _indexes.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<PlayerException> get errorStream => _errors.stream;

  @override
  bool get hasPrevious => hasPreviousValue;

  @override
  bool get hasNext => hasNextValue;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    currentIndex = initialIndex;
    _indexes.add(initialIndex);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    removedIndexes.add(index);

    final emittedIndex = indexToEmitDuringRemoval;

    if (emittedIndex != null) {
      _indexes.add(emittedIndex);

      // Allow the engine's index listener to run before this mutation returns.
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {
    if (index != null) {
      currentIndex = index;
      _indexes.add(index);
    }
  }

  @override
  Future<void> seekToNext() async {
    final index = currentIndex;

    if (index == null) {
      return;
    }

    final nextIndex = index + 1;
    currentIndex = nextIndex;
    _indexes.add(nextIndex);
  }

  @override
  Future<void> seekToPrevious() async {
    final index = currentIndex;

    if (index == null) {
      return;
    }

    final previousIndex = index - 1;
    currentIndex = previousIndex;
    _indexes.add(previousIndex);
  }

  void emitCurrentIndex(int index) {
    currentIndex = index;
    _indexes.add(index);
  }

  void emitPosition(Duration position) {
    _positions.add(position);
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async {}

  @override
  Future<void> moveAudioSource(int oldIndex, int newIndex) async {}

  @override
  Future<void> shuffle() async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _indexes.close();
    await _playerStates.close();
    await _errors.close();
  }
}

PlaybackTrack track(String id) {
  return PlaybackTrack(
    songId: id,
    title: id,
    artistId: 'artist-1',
    artistName: 'Artist',
    albumId: 'album-1',
    albumTitle: 'Album',
    filePath: 'C:/Music/$id.mp3',
    duration: const Duration(minutes: 3),
  );
}

void main() {
  test('loadQueue rejects a blocked playback track', () async {
    final player = FakePlaybackAudioPlayer();
    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    final blockedTrack = track('blocked-song').copyWith(isSongBlocked: true);

    await expectLater(engine.loadQueue([blockedTrack]), throwsArgumentError);

    expect(engine.currentState.queue.isEmpty, isTrue);

    await engine.dispose();
  });

  test('insertTrack rejects an artist-blocked playback track', () async {
    final player = FakePlaybackAudioPlayer();
    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([track('song-1')]);

    final blockedTrack = track(
      'blocked-artist-song',
    ).copyWith(isArtistBlacklisted: true);

    await expectLater(
      engine.insertTrack(blockedTrack, index: 1),
      throwsArgumentError,
    );

    expect(engine.currentState.queue.tracks.map((track) => track.songId), [
      'song-1',
    ]);

    await engine.dispose();
  });

  test(
    'removing current source ignores stale current-index event during mutation',
    () async {
      final player = FakePlaybackAudioPlayer();
      final engine = JustAudioPlaybackEngine(
        audioPlayer: player,
        configureAudioSession: () async {},
      );

      await engine.loadQueue([
        track('song-1'),
        track('song-2'),
        track('song-3'),
      ], startIndex: 1);

      await Future<void>.delayed(Duration.zero);

      expect(engine.currentState.queue.currentTrack?.songId, 'song-2');

      final emittedCurrentSongIds = <String?>[];
      final subscription = engine.states.listen((state) {
        emittedCurrentSongIds.add(state.queue.currentTrack?.songId);
      });

      player.indexToEmitDuringRemoval = 1;

      await engine.removeTrackAt(1);
      await Future<void>.delayed(Duration.zero);

      expect(player.removedIndexes, [1]);
      expect(engine.currentState.queue.tracks.map((track) => track.songId), [
        'song-1',
        'song-3',
      ]);
      expect(engine.currentState.queue.currentIndex, 1);
      expect(engine.currentState.queue.currentTrack?.songId, 'song-3');

      // The structural mutation must never republish removed song-2 as though
      // it were a genuine playback transition.
      expect(emittedCurrentSongIds.where((id) => id == 'song-2'), isEmpty);

      await subscription.cancel();
      await engine.dispose();
    },
  );

  test('removing source before current preserves current identity', () async {
    final player = FakePlaybackAudioPlayer();
    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([
      track('song-1'),
      track('song-2'),
      track('song-3'),
    ], startIndex: 2);

    await Future<void>.delayed(Duration.zero);

    player.indexToEmitDuringRemoval = 1;

    await engine.removeTrackAt(0);
    await Future<void>.delayed(Duration.zero);

    expect(engine.currentState.queue.tracks.map((track) => track.songId), [
      'song-2',
      'song-3',
    ]);
    expect(engine.currentState.queue.currentIndex, 1);
    expect(engine.currentState.queue.currentTrack?.songId, 'song-3');

    await engine.dispose();
  });

  test('skipNext identifies explicit next transition', () async {
    final player = FakePlaybackAudioPlayer()..hasNextValue = true;

    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([track('song-1'), track('song-2')]);

    await Future<void>.delayed(Duration.zero);

    await engine.skipNext();
    await Future<void>.delayed(Duration.zero);

    expect(engine.currentState.queue.currentTrack?.songId, 'song-2');
    expect(
      engine.currentState.transitionCause,
      PlaybackTransitionCause.skipNext,
    );

    await engine.dispose();
  });

  test('skipPrevious identifies explicit previous transition', () async {
    final player = FakePlaybackAudioPlayer()..hasPreviousValue = true;

    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([track('song-1'), track('song-2')], startIndex: 1);

    await Future<void>.delayed(Duration.zero);

    await engine.skipPrevious();
    await Future<void>.delayed(Duration.zero);

    expect(engine.currentState.queue.currentTrack?.songId, 'song-1');
    expect(
      engine.currentState.transitionCause,
      PlaybackTransitionCause.skipPrevious,
    );

    await engine.dispose();
  });

  test('skipToIndex identifies explicit indexed transition', () async {
    final player = FakePlaybackAudioPlayer();

    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([track('song-1'), track('song-2'), track('song-3')]);

    await Future<void>.delayed(Duration.zero);

    await engine.skipToIndex(2);
    await Future<void>.delayed(Duration.zero);

    expect(engine.currentState.queue.currentTrack?.songId, 'song-3');
    expect(
      engine.currentState.transitionCause,
      PlaybackTransitionCause.skipToIndex,
    );

    await engine.dispose();
  });

  test('external index change identifies automatic transition', () async {
    final player = FakePlaybackAudioPlayer();

    final engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );

    await engine.loadQueue([track('song-1'), track('song-2')]);

    await Future<void>.delayed(Duration.zero);

    player.emitCurrentIndex(1);
    await Future<void>.delayed(Duration.zero);

    expect(engine.currentState.queue.currentTrack?.songId, 'song-2');
    expect(
      engine.currentState.transitionCause,
      PlaybackTransitionCause.automatic,
    );

    await engine.dispose();
  });

  test(
    'unrelated position emission clears one-shot transition cause',
    () async {
      final player = FakePlaybackAudioPlayer()..hasNextValue = true;

      final engine = JustAudioPlaybackEngine(
        audioPlayer: player,
        configureAudioSession: () async {},
      );

      await engine.loadQueue([track('song-1'), track('song-2')]);

      await Future<void>.delayed(Duration.zero);

      await engine.skipNext();
      await Future<void>.delayed(Duration.zero);

      expect(
        engine.currentState.transitionCause,
        PlaybackTransitionCause.skipNext,
      );

      player.emitPosition(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);

      expect(engine.currentState.transitionCause, isNull);

      await engine.dispose();
    },
  );
}
