import 'dart:async';

import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

PlaybackTrack mediaTrack(String id, {String? artworkPath}) => PlaybackTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist-$id',
  artistName: 'Artist $id',
  albumId: 'album-$id',
  albumTitle: 'Album $id',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
  artworkPath: artworkPath,
);

PlaybackState queuedState({
  PlaybackStatus status = PlaybackStatus.playing,
  int index = 0,
  Duration position = Duration.zero,
  Duration duration = const Duration(minutes: 3),
  List<PlaybackTrack>? tracks,
  bool shuffle = false,
  PlaybackRepeatMode repeat = PlaybackRepeatMode.off,
}) {
  return PlaybackState(
    queue: PlaybackQueue(
      tracks: tracks ?? [mediaTrack('a'), mediaTrack('b'), mediaTrack('c')],
      currentIndex: index,
    ),
    status: status,
    position: position,
    duration: duration,
    shuffleEnabled: shuffle,
    repeatMode: repeat,
  );
}

/// A playback engine that records every command and emits states on
/// demand. Commands do not change state by themselves, so tests control
/// exactly what the media session sees.
class RecordingEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  final List<String> commands = [];
  Object? failWith;

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

  Future<void> _record(String command) async {
    commands.add(command);
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Future<void> play() => _record('play');

  @override
  Future<void> pause() => _record('pause');

  @override
  Future<void> seek(Duration position) => _record('seek:${position.inSeconds}');

  @override
  Future<void> skipNext() => _record('skipNext');

  @override
  Future<void> skipPrevious() => _record('skipPrevious');

  @override
  Future<void> skipToIndex(int index) => _record('skipToIndex:$index');

  @override
  Future<void> setShuffleEnabled(bool enabled) => _record('shuffle:$enabled');

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      _record('repeat:${mode.name}');

  @override
  Future<void> stop() => _record('stop');

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) => _record('loadQueue');

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) =>
      _record('insertTrack');

  @override
  Future<void> appendTrack(PlaybackTrack track) => _record('appendTrack');

  @override
  Future<void> removeTrackAt(int index) => _record('removeTrackAt');

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) =>
      _record('moveTrack');

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}
