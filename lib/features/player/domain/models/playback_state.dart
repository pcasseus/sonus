import 'playback_queue.dart';
import 'playback_repeat_mode.dart';
import 'playback_transition_cause.dart';

enum PlaybackStatus { idle, loading, ready, playing, paused, completed, failed }

class PlaybackState {
  const PlaybackState({
    this.queue = const PlaybackQueue(),
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = PlaybackRepeatMode.off,
    this.shuffleEnabled = false,
    this.transitionCause,
    this.errorMessage,
    this.nextAvailable,
    this.previousAvailable,
  });

  final PlaybackQueue queue;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final PlaybackRepeatMode repeatMode;
  final bool shuffleEnabled;
  final PlaybackTransitionCause? transitionCause;
  final String? errorMessage;

  /// Whether the player has a next or previous song. The player follows
  /// the shuffle order and wraps with repeat all, which the queue's list
  /// order cannot show. Null when the engine does not report it.
  final bool? nextAvailable;
  final bool? previousAvailable;

  bool get canSkipNext => nextAvailable ?? queue.hasNext;

  bool get canSkipPrevious => previousAvailable ?? queue.hasPrevious;

  bool get hasTrack => queue.currentTrack != null;

  bool get isPlaying => status == PlaybackStatus.playing;

  bool get hasError => status == PlaybackStatus.failed;

  double get progress {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }

    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  PlaybackState copyWith({
    PlaybackQueue? queue,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    PlaybackRepeatMode? repeatMode,
    bool? shuffleEnabled,
    PlaybackTransitionCause? transitionCause,
    bool clearTransitionCause = false,
    String? errorMessage,
    bool clearError = false,
    bool? nextAvailable,
    bool? previousAvailable,
  }) {
    return PlaybackState(
      queue: queue ?? this.queue,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      transitionCause: clearTransitionCause
          ? null
          : transitionCause ?? this.transitionCause,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      nextAvailable: nextAvailable ?? this.nextAvailable,
      previousAvailable: previousAvailable ?? this.previousAvailable,
    );
  }
}
