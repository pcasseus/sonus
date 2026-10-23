// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/models/playback_transition_cause.dart';
import '../../../player/domain/models/playback_track.dart';
import '../../domain/entities/playback_session.dart';
import '../services/listening_session_start.dart';
import '../services/listening_session_tracker.dart';

typedef PlaybackAnalyticsNow = DateTime Function();
typedef PlaybackAnalyticsUserIdProvider = String? Function();
typedef PlaybackAnalyticsErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class PlaybackAnalyticsController {
  PlaybackAnalyticsController({
    required PlaybackCoordinator playbackCoordinator,
    required ListeningSessionTracker tracker,
    Duration checkpointInterval = const Duration(seconds: 5),
    PlaybackAnalyticsNow? now,
    PlaybackAnalyticsUserIdProvider? userIdProvider,
    PlaybackAnalyticsErrorHandler? onError,
  }) : _playbackCoordinator = playbackCoordinator,
       _tracker = tracker,
       _checkpointInterval = checkpointInterval,
       _now = now ?? DateTime.now,
       _userIdProvider = userIdProvider,
       _onError = onError {
    _subscription = _playbackCoordinator.states.listen(_enqueueState);

    _enqueueState(_playbackCoordinator.currentState);
  }

  final PlaybackCoordinator _playbackCoordinator;
  final ListeningSessionTracker _tracker;
  final Duration _checkpointInterval;
  final PlaybackAnalyticsNow _now;
  final PlaybackAnalyticsUserIdProvider? _userIdProvider;
  final PlaybackAnalyticsErrorHandler? _onError;

  late final StreamSubscription<PlaybackState> _subscription;

  PlaybackState? _previousState;
  DateTime? _lastCheckpointAt;

  Future<void> _pending = Future<void>.value();

  bool _disposed = false;

  /// Set while a library restore is pending or has replaced the library.
  bool _suspended = false;

  Object? _lastError;

  Object? get lastError => _lastError;

  Future<void> get settled => _pending;

  bool get isSuspended => _suspended;

  /// Stops recording playback for a library restore. Call it after playback
  /// has stopped; the returned future completes once every queued analytics
  /// write has finished.
  ///
  /// The coordinator's current state is queued and suspension starts in the
  /// same synchronous step, so the end of the session is recorded even if
  /// the engine has not delivered its idle state yet, and nothing delivered
  /// afterwards is recorded. A session the drain could not end is abandoned
  /// so it is never written into a restored library.
  Future<void> suspendForRestore() {
    if (_disposed || _suspended) {
      return _pending;
    }

    _enqueueState(_playbackCoordinator.currentState);
    _suspended = true;

    _pending = _pending.then((_) {
      if (_tracker.hasActiveSession) {
        _tracker.abandon();
      }
    });

    return _pending;
  }

  /// Records playback again after a restore that did not change the library.
  void resumeAfterRestore() {
    if (_disposed || !_suspended) {
      return;
    }

    _suspended = false;
    _enqueueState(_playbackCoordinator.currentState);
  }

  Future<void> attachActiveSessionToUser(String userId) {
    if (_disposed) {
      return Future<void>.error(
        StateError('Playback analytics controller is disposed.'),
      );
    }

    // A suspended controller has no active session to attach.
    if (_suspended) {
      return Future<void>.value();
    }

    final completer = Completer<void>();

    _pending = _pending.then((_) async {
      try {
        await _tracker.attachCurrentSessionToUser(userId);

        completer.complete();
      } catch (error, stackTrace) {
        _lastError = error;
        _onError?.call(error, stackTrace);

        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  void _enqueueState(PlaybackState state) {
    if (_disposed || _suspended) {
      return;
    }

    _pending = _pending.then((_) => _handleState(state)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _lastError = error;
      _onError?.call(error, stackTrace);
    });
  }

  Future<void> _handleState(PlaybackState state) async {
    if (_disposed) {
      return;
    }

    final previous = _previousState;
    final track = state.queue.currentTrack;

    if (_tracker.hasActiveSession) {
      final activeSongId = _tracker.currentSession!.songId;

      if (track == null || track.songId != activeSongId) {
        await _tracker.end(
          reason: _endReasonForTrackChange(previous, state),
          position:
              previous?.position ?? _tracker.currentSession!.finalPosition,
          trackDuration: _resolvedDuration(previous),
        );

        _lastCheckpointAt = null;
      } else if (_looksLikeCompletedRestart(previous, state)) {
        await _tracker.end(
          reason: PlaybackSessionEndReason.completed,
          position: previous!.position,
          trackDuration: _resolvedDuration(previous),
        );

        _lastCheckpointAt = null;
      }
    }

    if (track == null) {
      _previousState = state;
      return;
    }

    if (!_tracker.hasActiveSession) {
      if (state.status == PlaybackStatus.playing) {
        await _startForTrack(track, state);
      }

      _previousState = state;
      return;
    }

    switch (state.status) {
      case PlaybackStatus.playing:
        await _handlePlaying(state);
        break;

      case PlaybackStatus.paused:
      case PlaybackStatus.ready:
      case PlaybackStatus.loading:
        if (_tracker.isPlaying) {
          await _tracker.markPaused(
            position: state.position,
            trackDuration: _resolvedDuration(state),
          );
        }
        break;

      case PlaybackStatus.completed:
        await _tracker.end(
          reason: PlaybackSessionEndReason.completed,
          position: state.position,
          trackDuration: _resolvedDuration(state),
        );
        _lastCheckpointAt = null;
        break;

      case PlaybackStatus.failed:
        await _tracker.end(
          reason: PlaybackSessionEndReason.failed,
          position: state.position,
          trackDuration: _resolvedDuration(state),
        );
        _lastCheckpointAt = null;
        break;

      case PlaybackStatus.idle:
        await _tracker.end(
          reason: PlaybackSessionEndReason.stopped,
          position: state.position,
          trackDuration: _resolvedDuration(state),
        );
        _lastCheckpointAt = null;
        break;
    }

    _previousState = state;
  }

  Future<void> _startForTrack(PlaybackTrack track, PlaybackState state) async {
    final albumEditionId = track.albumEditionId;

    if (albumEditionId == null || albumEditionId.trim().isEmpty) {
      throw StateError(
        'Playback track ${track.songId} is missing an album edition id.',
      );
    }

    await _tracker.start(
      ListeningSessionStart(
        userId: _currentUserId(),
        songId: track.songId,
        artistId: track.artistId,
        albumId: track.albumId,
        albumEditionId: albumEditionId,
        songTitle: track.title,
        artistName: track.artistName,
        albumTitle: track.albumTitle,
        albumEditionTitle: track.albumEditionTitle?.trim().isNotEmpty == true
            ? track.albumEditionTitle!
            : track.albumTitle,
        trackDuration: _resolvedDuration(state) ?? track.duration,
      ),
      initialPosition: state.position,
      playing: true,
    );

    _lastCheckpointAt = _utcNow();
  }

  Future<void> _handlePlaying(PlaybackState state) async {
    if (!_tracker.isPlaying) {
      await _tracker.markPlaying(
        position: state.position,
        trackDuration: _resolvedDuration(state),
      );

      _lastCheckpointAt = _utcNow();
      return;
    }

    final now = _utcNow();
    final lastCheckpointAt = _lastCheckpointAt;

    if (lastCheckpointAt == null ||
        now.difference(lastCheckpointAt) >= _checkpointInterval) {
      await _tracker.checkpoint(
        position: state.position,
        trackDuration: _resolvedDuration(state),
      );

      _lastCheckpointAt = now;
    }
  }

  PlaybackSessionEndReason _endReasonForTrackChange(
    PlaybackState? previous,
    PlaybackState current,
  ) {
    switch (current.transitionCause) {
      case PlaybackTransitionCause.skipNext:
      case PlaybackTransitionCause.skipPrevious:
      case PlaybackTransitionCause.skipToIndex:
        return PlaybackSessionEndReason.skipped;

      case PlaybackTransitionCause.automatic:
        return PlaybackSessionEndReason.completed;

      case null:
        break;
    }

    if (previous == null) {
      return PlaybackSessionEndReason.replaced;
    }

    if (previous.status == PlaybackStatus.completed ||
        _wasNearTrackEnd(previous)) {
      return PlaybackSessionEndReason.completed;
    }

    return PlaybackSessionEndReason.skipped;
  }

  bool _looksLikeCompletedRestart(
    PlaybackState? previous,
    PlaybackState current,
  ) {
    if (previous == null) {
      return false;
    }

    final previousTrack = previous.queue.currentTrack;
    final currentTrack = current.queue.currentTrack;

    if (previousTrack == null ||
        currentTrack == null ||
        previousTrack.songId != currentTrack.songId) {
      return false;
    }

    if (!_wasNearTrackEnd(previous)) {
      return false;
    }

    return current.status == PlaybackStatus.playing &&
        current.position <= const Duration(seconds: 2) &&
        current.position < previous.position;
  }

  bool _wasNearTrackEnd(PlaybackState state) {
    final duration = _resolvedDuration(state);

    if (duration == null || duration <= Duration.zero) {
      return false;
    }

    final remaining = duration - state.position;

    return remaining <= const Duration(seconds: 2);
  }

  Duration? _resolvedDuration(PlaybackState? state) {
    if (state == null) {
      return null;
    }

    if (state.duration > Duration.zero) {
      return state.duration;
    }

    final trackDuration = state.queue.currentTrack?.duration;

    if (trackDuration != null && trackDuration > Duration.zero) {
      return trackDuration;
    }

    return null;
  }

  String? _currentUserId() {
    final userId = _userIdProvider?.call()?.trim();

    if (userId == null || userId.isEmpty) {
      return null;
    }

    return userId;
  }

  DateTime _utcNow() => _now().toUtc();

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _subscription.cancel();
    await _pending;

    // A suspended controller belongs to a library that is being, or has
    // been, replaced by a restore; it must not write on the way out.
    if (!_suspended && _tracker.hasActiveSession) {
      final previous = _previousState;

      await _tracker.end(
        reason: PlaybackSessionEndReason.interrupted,
        position: previous?.position ?? _tracker.currentSession!.finalPosition,
        trackDuration: _resolvedDuration(previous),
      );
    }
  }
}
