import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState state = const PlaybackState();

  List<PlaybackTrack>? loadedTracks;
  int? loadedStartIndex;
  bool? loadedAutoPlay;

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  int? insertedIndex;
  PlaybackTrack? insertedTrack;

  PlaybackTrack? appendedTrack;

  int? removedIndex;
  final List<int> removedIndices = [];

  int? movedOldIndex;
  int? movedNewIndex;

  @override
  PlaybackState get currentState => state;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    loadedTracks = tracks;
    loadedStartIndex = startIndex;
    loadedAutoPlay = autoPlay;
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
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
    insertedTrack = track;
    insertedIndex = index;
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    appendedTrack = track;
  }

  @override
  Future<void> removeTrackAt(int index) async {
    removedIndex = index;
    removedIndices.add(index);
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) async {
    movedOldIndex = oldIndex;
    movedNewIndex = newIndex;
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  LibraryTrack track({
    required String songId,
    bool isAvailable = true,
    bool isSongBlocked = false,
    String? filePath,
  }) {
    return LibraryTrack(
      songId: songId,
      title: songId,
      artistId: 'artist_1',
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      albumEditionId: 'edition_1',
      albumEditionTitle: 'Album',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 9, 11),
      isAvailable: isAvailable,
      isSongBlocked: isSongBlocked,
      filePath: filePath ?? 'C:/Music/$songId.mp3',
    );
  }

  PlaybackTrack playbackTrack(String songId, {String artistId = 'artist_1'}) {
    return PlaybackTrack(
      songId: songId,
      title: songId,
      artistId: artistId,
      artistName: 'Artist',
      albumId: 'album_1',
      albumTitle: 'Album',
      filePath: 'C:/Music/$songId.mp3',
      duration: const Duration(minutes: 3),
    );
  }

  test('plays a single available library track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.playTrack(track(songId: 'song_1'));

    expect(engine.loadedTracks, hasLength(1));
    expect(engine.loadedTracks!.single.songId, 'song_1');
    expect(engine.loadedStartIndex, 0);
    expect(engine.loadedAutoPlay, isTrue);
  });

  test('rejects unavailable single track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    expect(
      () => coordinator.playTrack(track(songId: 'song_1', isAvailable: false)),
      throwsStateError,
    );
  });

  test(
    'filters unavailable tracks while preserving requested start track',
    () async {
      final engine = FakePlaybackEngine();
      final coordinator = PlaybackCoordinator(engine: engine);

      await coordinator.playTracks([
        track(songId: 'song_1'),
        track(songId: 'song_2', isAvailable: false),
        track(songId: 'song_3'),
      ], startIndex: 2);

      expect(engine.loadedTracks!.map((track) => track.songId), [
        'song_1',
        'song_3',
      ]);

      expect(engine.loadedStartIndex, 1);
    },
  );

  test('rejects unavailable requested start track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    expect(
      () => coordinator.playTracks([
        track(songId: 'song_1'),
        track(songId: 'song_2', isAvailable: false),
        track(songId: 'song_3'),
      ], startIndex: 1),
      throwsStateError,
    );
  });

  test('rejects explicitly blocked single track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    expect(
      () => coordinator.playTrack(track(songId: 'song_1', isSongBlocked: true)),
      throwsStateError,
    );

    expect(engine.loadedTracks, isNull);
  });

  test('filters blocked tracks from multi-track playback', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.playTracks([
      track(songId: 'song_1'),
      track(songId: 'song_2', isSongBlocked: true),
      track(songId: 'song_3'),
    ], startIndex: 2);

    expect(engine.loadedTracks!.map((track) => track.songId), [
      'song_1',
      'song_3',
    ]);

    expect(engine.loadedStartIndex, 1);
  });

  test('rejects blocked requested start track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    expect(
      () => coordinator.playTracks([
        track(songId: 'song_1'),
        track(songId: 'song_2', isSongBlocked: true),
        track(songId: 'song_3'),
      ], startIndex: 1),
      throwsStateError,
    );
  });

  test('rejects blocked play-next and add-to-queue tracks', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await expectLater(
      coordinator.playNext(track(songId: 'song_2', isSongBlocked: true)),
      throwsStateError,
    );

    await expectLater(
      coordinator.addToQueue(track(songId: 'song_3', isSongBlocked: true)),
      throwsStateError,
    );

    expect(engine.insertedTrack, isNull);
    expect(engine.appendedTrack, isNull);
  });
  test('empty track list stops playback', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.playTracks([]);

    expect(engine.stopCalls, 1);
  });

  test('toggle pauses when currently playing', () async {
    final engine = FakePlaybackEngine()
      ..state = const PlaybackState(status: PlaybackStatus.playing);

    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.togglePlayPause();

    expect(engine.pauseCalls, 1);
    expect(engine.playCalls, 0);
  });

  test('toggle plays when not currently playing', () async {
    final engine = FakePlaybackEngine()
      ..state = const PlaybackState(status: PlaybackStatus.paused);

    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.togglePlayPause();

    expect(engine.playCalls, 1);
    expect(engine.pauseCalls, 0);
  });

  test('play next inserts after current queue position', () async {
    final engine = FakePlaybackEngine()
      ..state = PlaybackState(
        queue: const PlaybackQueue().replace(
          tracks: const [
            PlaybackTrack(
              songId: 'song_1',
              title: 'song_1',
              artistId: 'artist_1',
              artistName: 'Artist',
              albumId: 'album_1',
              albumTitle: 'Album',
              filePath: 'C:/Music/song_1.mp3',
              duration: Duration(minutes: 3),
            ),
            PlaybackTrack(
              songId: 'song_3',
              title: 'song_3',
              artistId: 'artist_1',
              artistName: 'Artist',
              albumId: 'album_1',
              albumTitle: 'Album',
              filePath: 'C:/Music/song_3.mp3',
              duration: Duration(minutes: 3),
            ),
          ],
        ),
      );

    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.playNext(track(songId: 'song_2'));

    expect(engine.insertedTrack?.songId, 'song_2');
    expect(engine.insertedIndex, 1);
  });

  test('add to queue appends playable track', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.addToQueue(track(songId: 'song_2'));

    expect(engine.appendedTrack?.songId, 'song_2');
  });

  test('remove from queue delegates requested index', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.removeFromQueue(3);

    expect(engine.removedIndex, 3);
  });

  test('move queue track delegates queue reorder', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.moveQueueTrack(oldIndex: 4, newIndex: 1);

    expect(engine.movedOldIndex, 4);
    expect(engine.movedNewIndex, 1);
  });

  test('removes blocked non-current song from live queue', () async {
    final engine = FakePlaybackEngine()
      ..state = PlaybackState(
        queue: const PlaybackQueue().replace(
          tracks: [
            playbackTrack('song_1'),
            playbackTrack('song_2'),
            playbackTrack('song_3'),
          ],
          startIndex: 0,
        ),
        status: PlaybackStatus.playing,
      );
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.removeBlockedSongFromQueue('song_2');

    expect(engine.removedIndices, [1]);
    expect(engine.stopCalls, 0);
  });

  test(
    'removing current blocked song continues toward surviving next track',
    () async {
      final engine = FakePlaybackEngine()
        ..state = PlaybackState(
          queue: const PlaybackQueue().replace(
            tracks: [
              playbackTrack('song_1'),
              playbackTrack('song_2'),
              playbackTrack('song_3'),
            ],
            startIndex: 1,
          ),
          status: PlaybackStatus.playing,
        );
      final coordinator = PlaybackCoordinator(engine: engine);

      await coordinator.removeBlockedSongFromQueue('song_2');

      expect(engine.removedIndices, [1]);
      expect(engine.stopCalls, 0);
    },
  );

  test(
    'removing current blocked song stops when no surviving next track exists',
    () async {
      final engine = FakePlaybackEngine()
        ..state = PlaybackState(
          queue: const PlaybackQueue().replace(
            tracks: [playbackTrack('song_1'), playbackTrack('song_2')],
            startIndex: 1,
          ),
          status: PlaybackStatus.playing,
        );
      final coordinator = PlaybackCoordinator(engine: engine);

      await coordinator.removeBlockedSongFromQueue('song_2');

      expect(engine.stopCalls, 1);
      expect(engine.removedIndices, [1]);
    },
  );

  test('generic queue sanitation removes multiple song identities', () async {
    final engine = FakePlaybackEngine()
      ..state = PlaybackState(
        queue: const PlaybackQueue().replace(
          tracks: [
            playbackTrack('song_1'),
            playbackTrack('song_2'),
            playbackTrack('song_3'),
          ],
          startIndex: 0,
        ),
        status: PlaybackStatus.playing,
      );

    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.removeSongsFromQueue({'song_2', 'song_3'});

    expect(engine.removedIndices, [2, 1]);
    expect(engine.stopCalls, 0);
  });

  test('queue sanitation is a no-op when identity is not queued', () async {
    final engine = FakePlaybackEngine()
      ..state = PlaybackState(
        queue: const PlaybackQueue().replace(
          tracks: [playbackTrack('song_1'), playbackTrack('song_2')],
        ),
      );
    final coordinator = PlaybackCoordinator(engine: engine);

    await coordinator.removeBlockedSongFromQueue('missing-song');

    expect(engine.removedIndices, isEmpty);
    expect(engine.stopCalls, 0);
  });
}
