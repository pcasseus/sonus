import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';
import 'package:sonus_next/features/player/domain/repositories/track_lyrics_repository.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_state.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState state = const PlaybackState();

  @override
  PlaybackState get currentState => state;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void emit(PlaybackState newState) {
    state = newState;
    _controller.add(newState);
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class FakeTrackLyricsRepository implements TrackLyricsRepository {
  final Map<String, TrackLyrics?> lyricsBySongId = {};
  final Map<String, Object> errorsBySongId = {};
  final Map<String, Completer<TrackLyrics?>> pendingBySongId = {};

  final List<String> requestedSongIds = [];

  @override
  Future<TrackLyrics?> getBySongId(String songId) {
    requestedSongIds.add(songId);

    final pending = pendingBySongId[songId];
    if (pending != null) {
      return pending.future;
    }

    final error = errorsBySongId[songId];
    if (error != null) {
      return Future<TrackLyrics?>.error(error);
    }

    return Future<TrackLyrics?>.value(lyricsBySongId[songId]);
  }

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) async {}

  @override
  Future<void> deleteBySongId(String songId) async {}
}

PlaybackTrack track(String songId) {
  return PlaybackTrack(
    songId: songId,
    title: 'Song $songId',
    artistId: 'artist-$songId',
    artistName: 'Artist',
    albumId: 'album-$songId',
    albumTitle: 'Album $songId',
    duration: const Duration(minutes: 3),
    filePath: 'C:/Music/$songId.mp3',
  );
}

PlaybackState playbackStateFor(
  String songId, {
  Duration position = Duration.zero,
}) {
  return PlaybackState(
    queue: PlaybackQueue(tracks: [track(songId)], currentIndex: 0),
    status: PlaybackStatus.playing,
    position: position,
    duration: const Duration(minutes: 3),
  );
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('loads lyrics for the coordinator current track', () async {
    final engine = FakePlaybackEngine()..state = playbackStateFor('song-1');

    final repository = FakeTrackLyricsRepository()
      ..lyricsBySongId['song-1'] = const TrackLyrics(
        songId: 'song-1',
        plainText: 'Current lyrics',
      );

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    await flushAsync();

    expect(repository.requestedSongIds, ['song-1']);
    expect(controller.state.status, LyricsStatus.loaded);
    expect(controller.state.songId, 'song-1');
    expect(controller.state.lyrics?.plainText, 'Current lyrics');

    controller.dispose();
    await engine.dispose();
  });

  test('loads lyrics when the current track changes', () async {
    final engine = FakePlaybackEngine();

    final repository = FakeTrackLyricsRepository()
      ..lyricsBySongId['song-2'] = const TrackLyrics(
        songId: 'song-2',
        plainText: 'Second lyrics',
      );

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    engine.emit(playbackStateFor('song-2'));
    await flushAsync();

    expect(repository.requestedSongIds, ['song-2']);
    expect(controller.state.status, LyricsStatus.loaded);
    expect(controller.state.songId, 'song-2');

    controller.dispose();
    await engine.dispose();
  });

  test('clears lyrics when playback no longer has a current track', () async {
    final engine = FakePlaybackEngine()..state = playbackStateFor('song-1');

    final repository = FakeTrackLyricsRepository()
      ..lyricsBySongId['song-1'] = const TrackLyrics(
        songId: 'song-1',
        plainText: 'Lyrics',
      );

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    await flushAsync();

    engine.emit(const PlaybackState());
    await flushAsync();

    expect(controller.state.status, LyricsStatus.idle);
    expect(controller.state.songId, isNull);
    expect(controller.state.lyrics, isNull);

    controller.dispose();
    await engine.dispose();
  });

  test('position updates for the same song do not reload lyrics', () async {
    final engine = FakePlaybackEngine()..state = playbackStateFor('song-1');

    final repository = FakeTrackLyricsRepository()
      ..lyricsBySongId['song-1'] = const TrackLyrics(
        songId: 'song-1',
        plainText: 'Lyrics',
      );

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    await flushAsync();

    engine.emit(
      playbackStateFor('song-1', position: const Duration(seconds: 30)),
    );
    await flushAsync();

    expect(repository.requestedSongIds, ['song-1']);
    expect(controller.state.status, LyricsStatus.loaded);

    controller.dispose();
    await engine.dispose();
  });

  test('reports empty state when lyrics are missing', () async {
    final engine = FakePlaybackEngine()..state = playbackStateFor('song-empty');

    final repository = FakeTrackLyricsRepository();

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    await flushAsync();

    expect(controller.state.songId, 'song-empty');
    expect(controller.state.status, LyricsStatus.empty);
    expect(controller.state.hasLyrics, isFalse);

    controller.dispose();
    await engine.dispose();
  });

  test('reports repository failures', () async {
    final engine = FakePlaybackEngine()..state = playbackStateFor('song-error');

    final repository = FakeTrackLyricsRepository()
      ..errorsBySongId['song-error'] = StateError('Lyrics failed');

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    await flushAsync();

    expect(controller.state.songId, 'song-error');
    expect(controller.state.status, LyricsStatus.failed);
    expect(controller.state.hasError, isTrue);
    expect(controller.state.error, isA<StateError>());

    controller.dispose();
    await engine.dispose();
  });

  test('ignores stale lyrics result after the current track changes', () async {
    final firstCompleter = Completer<TrackLyrics?>();
    final secondCompleter = Completer<TrackLyrics?>();

    final engine = FakePlaybackEngine()..state = playbackStateFor('song-a');

    final repository = FakeTrackLyricsRepository()
      ..pendingBySongId['song-a'] = firstCompleter
      ..pendingBySongId['song-b'] = secondCompleter;

    final controller = LyricsController(
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: repository,
    );

    expect(controller.state.songId, 'song-a');
    expect(controller.state.status, LyricsStatus.loading);

    engine.emit(playbackStateFor('song-b'));
    await flushAsync();

    expect(controller.state.songId, 'song-b');
    expect(controller.state.status, LyricsStatus.loading);

    secondCompleter.complete(
      const TrackLyrics(songId: 'song-b', plainText: 'Second track lyrics'),
    );
    await flushAsync();

    expect(controller.state.songId, 'song-b');
    expect(controller.state.lyrics?.plainText, 'Second track lyrics');

    firstCompleter.complete(
      const TrackLyrics(
        songId: 'song-a',
        plainText: 'Stale first track lyrics',
      ),
    );
    await flushAsync();

    expect(controller.state.songId, 'song-b');
    expect(controller.state.status, LyricsStatus.loaded);
    expect(controller.state.lyrics?.plainText, 'Second track lyrics');

    controller.dispose();
    await engine.dispose();
  });
}
