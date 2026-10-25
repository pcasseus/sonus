import '../../../library/application/models/library_track.dart';
import '../../domain/models/playback_repeat_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../../domain/services/playback_engine.dart';
import '../mappers/library_track_playback_mapper.dart';

class PlaybackCoordinator {
  factory PlaybackCoordinator({required PlaybackEngine engine}) {
    return PlaybackCoordinator._(engine);
  }

  const PlaybackCoordinator._(this._engine);

  final PlaybackEngine _engine;

  Stream<PlaybackState> get states => _engine.states;

  PlaybackState get currentState => _engine.currentState;

  Future<void> playTrack(LibraryTrack track, {bool autoPlay = true}) async {
    final playableTrack = _requirePlayableTrack(track);

    await _engine.loadQueue([
      LibraryTrackPlaybackMapper.toPlaybackTrack(playableTrack),
    ], autoPlay: autoPlay);
  }

  Future<void> playTracks(
    List<LibraryTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) {
      await _engine.stop();
      return;
    }

    if (startIndex < 0 || startIndex >= tracks.length) {
      throw RangeError.index(startIndex, tracks, 'startIndex');
    }

    final requestedTrack = tracks[startIndex];

    final playableTracks = tracks.where(isPlayable).toList(growable: false);

    if (playableTracks.isEmpty) {
      throw StateError('No playable tracks are available.');
    }

    final remappedStartIndex = playableTracks.indexWhere(
      (track) => track.songId == requestedTrack.songId,
    );

    if (remappedStartIndex == -1) {
      throw StateError('Requested start track is unavailable for playback.');
    }

    await _engine.loadQueue(
      LibraryTrackPlaybackMapper.toPlaybackTracks(playableTracks),
      startIndex: remappedStartIndex,
      autoPlay: autoPlay,
    );
  }

  /// Plays [track] with [context], the ordered list it was chosen from, as
  /// the queue: an album, playlist, chart or search result. Previous and
  /// Next then follow that list. Unplayable songs in [context] are skipped.
  /// A [track] that is not in [context] plays on its own.
  Future<void> playInContext(
    LibraryTrack track,
    List<LibraryTrack> context, {
    bool autoPlay = true,
  }) async {
    final startIndex = context.indexWhere(
      (candidate) => candidate.songId == track.songId,
    );

    if (startIndex == -1) {
      await playTrack(track, autoPlay: autoPlay);
      return;
    }

    await playTracks(context, startIndex: startIndex, autoPlay: autoPlay);
  }

  Future<void> togglePlayPause() async {
    if (currentState.isPlaying) {
      await _engine.pause();
      return;
    }

    await _engine.play();
  }

  Future<void> play() => _engine.play();

  Future<void> pause() => _engine.pause();

  Future<void> seek(Duration position) => _engine.seek(position);

  Future<void> skipNext() => _engine.skipNext();

  Future<void> skipPrevious() => _engine.skipPrevious();

  Future<void> skipToIndex(int index) => _engine.skipToIndex(index);

  Future<void> playNext(LibraryTrack track) async {
    final playableTrack = _requirePlayableTrack(track);

    final playbackTrack = LibraryTrackPlaybackMapper.toPlaybackTrack(
      playableTrack,
    );

    final queue = currentState.queue;

    if (queue.isEmpty || !queue.hasCurrentTrack) {
      await _engine.loadQueue([playbackTrack], autoPlay: false);
      return;
    }

    await _engine.insertTrack(playbackTrack, index: queue.currentIndex + 1);
  }

  Future<void> addToQueue(LibraryTrack track) async {
    final playableTrack = _requirePlayableTrack(track);

    await _engine.appendTrack(
      LibraryTrackPlaybackMapper.toPlaybackTrack(playableTrack),
    );
  }

  Future<void> removeBlockedSongFromQueue(String songId) {
    return removeSongFromQueue(songId);
  }

  Future<void> removeSongFromQueue(String songId) {
    return removeSongsFromQueue([songId]);
  }

  Future<void> removeSongsFromQueue(Iterable<String> songIds) async {
    final normalizedSongIds = songIds
        .map((songId) => songId.trim())
        .where((songId) => songId.isNotEmpty)
        .toSet();

    if (normalizedSongIds.isEmpty) {
      return;
    }

    await _removeQueuedTracksWhere(
      (track) => normalizedSongIds.contains(track.songId),
    );
  }

  Future<void> removeFromQueue(int index) {
    return _engine.removeTrackAt(index);
  }

  Future<void> moveQueueTrack({required int oldIndex, required int newIndex}) {
    return _engine.moveTrack(oldIndex: oldIndex, newIndex: newIndex);
  }

  Future<void> setShuffleEnabled(bool enabled) {
    return _engine.setShuffleEnabled(enabled);
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) {
    return _engine.setRepeatMode(mode);
  }

  Future<void> stop() => _engine.stop();

  Future<void> _removeQueuedTracksWhere(
    bool Function(PlaybackTrack track) shouldRemove,
  ) async {
    final queue = currentState.queue;

    if (queue.isEmpty) {
      return;
    }

    final matchingIndexes = <int>[];

    for (var index = 0; index < queue.length; index++) {
      final track = queue.trackAt(index);

      if (track != null && shouldRemove(track)) {
        matchingIndexes.add(index);
      }
    }

    if (matchingIndexes.isEmpty) {
      return;
    }

    final removesCurrent =
        queue.hasCurrentTrack && matchingIndexes.contains(queue.currentIndex);

    if (removesCurrent) {
      var hasSurvivingNextTrack = false;

      for (var index = queue.currentIndex + 1; index < queue.length; index++) {
        final track = queue.trackAt(index);

        if (track != null && !shouldRemove(track)) {
          hasSurvivingNextTrack = true;
          break;
        }
      }

      if (!hasSurvivingNextTrack) {
        await _engine.stop();
      }
    }

    for (final index in matchingIndexes.reversed) {
      await _engine.removeTrackAt(index);
    }
  }

  /// Whether [track] can be queued: not blacklisted, with an available
  /// audio file. The single definition used by every queue entry point.
  static bool isPlayable(LibraryTrack track) {
    return !track.isBlocked &&
        track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  LibraryTrack _requirePlayableTrack(LibraryTrack track) {
    if (!isPlayable(track)) {
      throw StateError('Track ${track.songId} is unavailable for playback.');
    }

    return track;
  }
}
