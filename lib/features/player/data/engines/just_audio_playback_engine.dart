import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/models/playback_queue.dart';
import '../../domain/models/playback_repeat_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../../domain/models/playback_transition_cause.dart';
import '../../domain/services/playback_engine.dart';
import 'support/playback_audio_player.dart';

class JustAudioPlaybackEngine implements PlaybackEngine {
  JustAudioPlaybackEngine({
    PlaybackAudioPlayer? audioPlayer,
    Future<void> Function()? configureAudioSession,
  }) : _audioPlayer = audioPlayer ?? JustAudioPlayerAdapter(),
       _configureAudioSessionOverride = configureAudioSession {
    _subscriptions.add(
      _audioPlayer.positionStream.listen(_handlePositionChanged),
    );

    _subscriptions.add(
      _audioPlayer.durationStream.listen(_handleDurationChanged),
    );

    _subscriptions.add(
      _audioPlayer.currentIndexStream.listen(_handleCurrentIndexChanged),
    );

    _subscriptions.add(
      _audioPlayer.playerStateStream.listen(_handlePlayerStateChanged),
    );

    _subscriptions.add(_audioPlayer.errorStream.listen(_handlePlayerError));
  }

  final PlaybackAudioPlayer _audioPlayer;
  final Future<void> Function()? _configureAudioSessionOverride;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlaybackState _state = const PlaybackState();

  bool _disposed = false;
  bool _isRemovingQueueTrack = false;
  PlaybackTransitionCause? _pendingTransitionCause;

  @override
  Stream<PlaybackState> get states => _stateController.stream;

  @override
  PlaybackState get currentState => _state;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    _ensureNotDisposed();

    if (tracks.isEmpty) {
      await stop();

      _emit(const PlaybackState(status: PlaybackStatus.idle));

      return;
    }

    final unplayableIndex = tracks.indexWhere(
      (track) => !track.hasPlayablePath || track.isBlocked,
    );

    if (unplayableIndex != -1) {
      throw ArgumentError.value(
        tracks[unplayableIndex].songId,
        'tracks[$unplayableIndex]',
        'Playback track is unavailable or blocked.',
      );
    }

    if (startIndex < 0 || startIndex >= tracks.length) {
      throw RangeError.index(startIndex, tracks, 'startIndex');
    }

    final queue = const PlaybackQueue().replace(
      tracks: tracks,
      startIndex: startIndex,
    );

    _emit(
      PlaybackState(
        queue: queue,
        status: PlaybackStatus.loading,
        repeatMode: _state.repeatMode,
        shuffleEnabled: _state.shuffleEnabled,
      ),
    );

    try {
      await _configureAudioSession();

      final sources = tracks.map(_audioSourceFor).toList(growable: false);

      final loadedDuration = await _audioPlayer.setAudioSources(
        sources,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );

      _emit(
        _state.copyWith(
          status: PlaybackStatus.ready,
          duration: loadedDuration ?? queue.currentTrack!.duration,
          position: Duration.zero,
          clearError: true,
        ),
      );

      if (autoPlay) {
        await play();
      }
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _ensureNotDisposed();

    if (!_state.hasTrack) {
      return;
    }

    try {
      await _audioPlayer.play();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _ensureNotDisposed();

    try {
      await _audioPlayer.pause();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _ensureNotDisposed();

    if (!_state.hasTrack) {
      return;
    }

    final duration = _state.duration;

    final clamped = duration > Duration.zero && position > duration
        ? duration
        : position < Duration.zero
        ? Duration.zero
        : position;

    try {
      await _audioPlayer.seek(clamped);
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> skipNext() async {
    _ensureNotDisposed();

    final canAdvance = _audioPlayer.hasNext;

    if (canAdvance) {
      _pendingTransitionCause = PlaybackTransitionCause.skipNext;
    }

    try {
      await _audioPlayer.seekToNext();
    } catch (error) {
      if (canAdvance &&
          _pendingTransitionCause == PlaybackTransitionCause.skipNext) {
        _pendingTransitionCause = null;
      }

      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> skipPrevious() async {
    _ensureNotDisposed();

    if (_state.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    if (!_audioPlayer.hasPrevious) {
      await seek(Duration.zero);
      return;
    }

    _pendingTransitionCause = PlaybackTransitionCause.skipPrevious;

    try {
      await _audioPlayer.seekToPrevious();
    } catch (error) {
      if (_pendingTransitionCause == PlaybackTransitionCause.skipPrevious) {
        _pendingTransitionCause = null;
      }

      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> skipToIndex(int index) async {
    _ensureNotDisposed();

    if (index < 0 || index >= _state.queue.length) {
      throw RangeError.index(index, _state.queue.tracks, 'index');
    }

    final changesTrack = index != _state.queue.currentIndex;

    if (changesTrack) {
      _pendingTransitionCause = PlaybackTransitionCause.skipToIndex;
    }

    try {
      await _audioPlayer.seek(Duration.zero, index: index);
    } catch (error) {
      if (changesTrack &&
          _pendingTransitionCause == PlaybackTransitionCause.skipToIndex) {
        _pendingTransitionCause = null;
      }

      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
    _ensureNotDisposed();

    if (!track.hasPlayablePath || track.isBlocked) {
      throw ArgumentError.value(
        track.songId,
        'track',
        'Playback track is unavailable or blocked.',
      );
    }

    if (index < 0 || index > _state.queue.length) {
      throw RangeError.range(index, 0, _state.queue.length, 'index');
    }

    final updatedQueue = _state.queue.insertTrack(track, index: index);

    try {
      await _audioPlayer.insertAudioSource(index, _audioSourceFor(track));

      _emit(_state.copyWith(queue: updatedQueue, clearError: true));
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    await insertTrack(track, index: _state.queue.length);
  }

  @override
  Future<void> removeTrackAt(int index) async {
    _ensureNotDisposed();

    if (index < 0 || index >= _state.queue.length) {
      throw RangeError.index(index, _state.queue.tracks, 'index');
    }

    final updatedQueue = _state.queue.removeTrackAt(index);

    try {
      _isRemovingQueueTrack = true;

      await _audioPlayer.removeAudioSourceAt(index);

      _emit(
        _state.copyWith(
          queue: updatedQueue,
          position: updatedQueue.isEmpty ? Duration.zero : _state.position,
          duration: updatedQueue.currentTrack?.duration ?? Duration.zero,
          clearError: true,
        ),
      );
    } catch (error) {
      _emitFailure(error);
      rethrow;
    } finally {
      _isRemovingQueueTrack = false;
    }
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) async {
    _ensureNotDisposed();

    if (oldIndex < 0 || oldIndex >= _state.queue.length) {
      throw RangeError.index(oldIndex, _state.queue.tracks, 'oldIndex');
    }

    if (newIndex < 0 || newIndex >= _state.queue.length) {
      throw RangeError.index(newIndex, _state.queue.tracks, 'newIndex');
    }

    if (oldIndex == newIndex) {
      return;
    }

    final updatedQueue = _state.queue.moveTrack(
      oldIndex: oldIndex,
      newIndex: newIndex,
    );

    try {
      await _audioPlayer.moveAudioSource(oldIndex, newIndex);

      _emit(_state.copyWith(queue: updatedQueue, clearError: true));
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    _ensureNotDisposed();

    try {
      if (enabled) {
        await _audioPlayer.shuffle();
      }

      await _audioPlayer.setShuffleModeEnabled(enabled);

      _emit(_state.copyWith(shuffleEnabled: enabled, clearError: true));
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _ensureNotDisposed();

    final loopMode = switch (mode) {
      PlaybackRepeatMode.off => LoopMode.off,
      PlaybackRepeatMode.one => LoopMode.one,
      PlaybackRepeatMode.all => LoopMode.all,
    };

    try {
      await _audioPlayer.setLoopMode(loopMode);

      _emit(_state.copyWith(repeatMode: mode, clearError: true));
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    await _audioPlayer.stop();

    _emit(
      PlaybackState(
        queue: _state.queue,
        status: PlaybackStatus.idle,
        repeatMode: _state.repeatMode,
        shuffleEnabled: _state.shuffleEnabled,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    await _audioPlayer.dispose();
    await _stateController.close();
  }

  AudioSource _audioSourceFor(PlaybackTrack track) {
    final source = track.filePath.trim();

    if (source.startsWith('content://')) {
      return AudioSource.uri(Uri.parse(source), tag: track.songId);
    }

    return AudioSource.file(source, tag: track.songId);
  }

  Future<void> _configureAudioSession() async {
    final override = _configureAudioSessionOverride;

    if (override != null) {
      await override();
      return;
    }

    final session = await AudioSession.instance;

    await session.configure(const AudioSessionConfiguration.music());
  }

  void _handlePositionChanged(Duration position) {
    if (_disposed) {
      return;
    }

    _emit(_state.copyWith(position: position, clearTransitionCause: true));
  }

  void _handleDurationChanged(Duration? duration) {
    if (_disposed || duration == null) {
      return;
    }

    _emit(_state.copyWith(duration: duration, clearTransitionCause: true));
  }

  void _handleCurrentIndexChanged(int? index) {
    if (_disposed || _isRemovingQueueTrack || index == null) {
      return;
    }

    if (index < 0 || index >= _state.queue.length) {
      return;
    }

    final previousIndex = _state.queue.currentIndex;

    if (index == previousIndex) {
      _pendingTransitionCause = null;
      return;
    }

    final transitionCause =
        _pendingTransitionCause ?? PlaybackTransitionCause.automatic;

    _pendingTransitionCause = null;

    _emit(
      _state.copyWith(
        queue: _state.queue.moveTo(index),
        position: Duration.zero,
        duration: _state.queue.trackAt(index)?.duration ?? Duration.zero,
        transitionCause: transitionCause,
      ),
    );
  }

  void _handlePlayerStateChanged(PlayerState state) {
    if (_disposed) {
      return;
    }

    final status = switch (state.processingState) {
      ProcessingState.idle => PlaybackStatus.idle,
      ProcessingState.loading ||
      ProcessingState.buffering => PlaybackStatus.loading,
      ProcessingState.ready =>
        state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      ProcessingState.completed => PlaybackStatus.completed,
    };

    _emit(
      _state.copyWith(
        status: status,
        clearError: true,
        clearTransitionCause: true,
      ),
    );
  }

  void _handlePlayerError(PlayerException error) {
    if (_disposed) {
      return;
    }

    _emitFailure(error);
  }

  void _emitFailure(Object error) {
    _emit(
      _state.copyWith(
        status: PlaybackStatus.failed,
        errorMessage: error.toString(),
        clearTransitionCause: true,
      ),
    );
  }

  void _emit(PlaybackState state) {
    _state = state;

    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Playback engine has been disposed.');
    }
  }
}
