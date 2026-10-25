import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';

/// Which song lists should mark as current, and whether it is playing.
///
/// A stopped, finished or failed session marks nothing. Lists listen to
/// [changes], which only emits when the song or play state changes, never
/// on position updates.
class NowPlayingMark {
  const NowPlayingMark({this.songId, this.isPlaying = false});

  factory NowPlayingMark.of(PlaybackState state) {
    final track = state.queue.currentTrack;
    final active = switch (state.status) {
      PlaybackStatus.idle ||
      PlaybackStatus.completed ||
      PlaybackStatus.failed => false,
      _ => true,
    };
    return active && track != null
        ? NowPlayingMark(songId: track.songId, isPlaying: state.isPlaying)
        : const NowPlayingMark();
  }

  static Stream<NowPlayingMark> changes(PlaybackCoordinator coordinator) =>
      coordinator.states.map(NowPlayingMark.of).distinct();

  final String? songId;
  final bool isPlaying;

  bool marks(String songId) => this.songId == songId;

  @override
  bool operator ==(Object other) =>
      other is NowPlayingMark &&
      other.songId == songId &&
      other.isPlaying == isPlaying;

  @override
  int get hashCode => Object.hash(songId, isPlaying);
}
