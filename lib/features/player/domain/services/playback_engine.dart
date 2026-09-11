import '../models/playback_repeat_mode.dart';
import '../models/playback_state.dart';
import '../models/playback_track.dart';

abstract interface class PlaybackEngine {
  Stream<PlaybackState> get states;
  PlaybackState get currentState;

  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> skipToIndex(int index);

  Future<void> insertTrack(PlaybackTrack track, {required int index});

  Future<void> appendTrack(PlaybackTrack track);

  Future<void> removeTrackAt(int index);

  Future<void> moveTrack({required int oldIndex, required int newIndex});

  Future<void> setShuffleEnabled(bool enabled);
  Future<void> setRepeatMode(PlaybackRepeatMode mode);

  Future<void> stop();
  Future<void> dispose();
}
