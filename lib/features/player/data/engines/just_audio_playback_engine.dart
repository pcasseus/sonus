import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/models/playback_queue.dart';
import '../../domain/models/playback_repeat_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../../domain/models/playback_transition_cause.dart';
import '../../domain/services/playback_engine.dart';
import '../../domain/services/shuffle_order_playback.dart';
import 'support/sonus_shuffle_order.dart';
import 'support/playback_audio_player.dart';

class JustAudioPlaybackEngine
    implements PlaybackEngine, PlaybackDisplayRefresh, ShuffleOrderPlayback {
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
  PlaybackTransitionCause? _pendingTransitionCause;

  /// BUG-05: the commands that change the queue, its order or the current
  /// entry run one at a time. Each one computes the new queue from the
  /// state the previous one left, so commands issued together (songs added
  /// from several menus, an album added song by song) can never overwrite
  /// each other and leave the engine's queue shorter than the player's.
  Future<void>? _inFlight;

  ///
  /// A command waiting for its turn when the engine is disposed is dropped
  /// when that turn comes: it was valid when it was issued, and the player
  /// it was for is gone (the playback scope is replaced, or Sonus closes).
  /// A command issued after disposal still fails, as before.
  Future<void> _inTurn(Future<void> Function() command) {
    final previous = _inFlight;
    // Idle: run now, so the command's first state change is synchronous,
    // exactly as before.
    final result = previous == null
        ? command()
        : previous.then((_) => _disposed ? null : command());
    final done = result.then<void>((_) {}, onError: (Object _) {});
    _inFlight = done;
    unawaited(
      done.then((_) {
        if (identical(_inFlight, done)) _inFlight = null;
      }),
    );
    return result;
  }

  /// While the player's sources are being changed, its index events are
  /// held back: an insert, move or removal shifts the current index, which
  /// is not a song change. The last one is reconciled when the change is
  /// done ([_reconcileIndexAfterQueueChange]).
  bool _changingQueue = false;
  int? _indexDuringQueueChange;

  @override
  Stream<PlaybackState> get states => _stateController.stream;

  @override
  PlaybackState get currentState => _state;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) => _inTurn(
    () => _loadQueue(tracks, startIndex: startIndex, autoPlay: autoPlay),
  );

  @override
  List<int>? get shuffleOrder {
    if (!_state.shuffleEnabled) return null;
    final order = _audioPlayer.shuffleIndices;
    return isShuffleOrderFor(order, _state.queue.length)
        ? List.unmodifiable(order)
        : null;
  }

  @override
  Future<void> loadQueueInShuffleOrder(
    List<PlaybackTrack> tracks, {
    required List<int> shuffleOrder,
    int startIndex = 0,
    bool autoPlay = false,
  }) => _inTurn(
    () => _loadQueue(
      tracks,
      startIndex: startIndex,
      autoPlay: autoPlay,
      shuffleOrder: isShuffleOrderFor(shuffleOrder, tracks.length)
          ? shuffleOrder
          : null,
    ),
  );

  Future<void> _loadQueue(
    List<PlaybackTrack> tracks, {
    required int startIndex,
    required bool autoPlay,
    List<int>? shuffleOrder,
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

      // just_audio keeps `playing` set across source changes, including
      // after a queue completes, so the new sources would start on their
      // own. A queue loaded without autoplay must stay silent.
      if (!autoPlay && _audioPlayer.playing) {
        await _audioPlayer.pause();
      }

      final sources = tracks.map(_audioSourceFor).toList(growable: false);

      final loadedDuration = await _audioPlayer.setAudioSources(
        sources,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
        // Always Sonus's order: a shuffle cycle never repeats an entry on
        // its own (SN-50 device QA), and a saved order is restored exactly.
        shuffleOrder: _shuffleOrder = SonusShuffleOrder(
          saved: shuffleOrder,
          currentIndex: () => _state.queue.currentIndex,
        ),
      );

      // When the player was already playing, the new queue is audible now
      // and play() below emits nothing, so report it as playing.
      _emit(
        _state.copyWith(
          status: _audioPlayer.playing
              ? PlaybackStatus.playing
              : PlaybackStatus.ready,
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
      final atEnd = _isAtEndOfQueue;
      _pausedAtSeekedPosition = false;

      // BUG-05: songs added after the queue finished. The player stays at
      // its end until it is moved, so Play goes on with the first of them,
      // as the queue reads, instead of replaying the finished song.
      if (_state.status == PlaybackStatus.completed) {
        final next = _audioPlayer.adjacentIndex(1);
        if (next != null &&
            next != _state.queue.currentIndex &&
            _state.repeatMode != PlaybackRepeatMode.all) {
          await _seekPlayer(Duration.zero, index: next);
          _startPlaying();
          return;
        }
      }

      if (atEnd) {
        await _replayFinalSong();
        return;
      }

      _startPlaying();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  /// Asks the player to play and returns at once (BUG-11).
  ///
  /// just_audio's play() Future completes only when playback later pauses,
  /// stops, reaches the end of the queue or is replaced by another play
  /// request; never when it starts. Awaiting it held the command queue
  /// ([_inTurn]) for the whole song after a queue was loaded with autoplay,
  /// so Shuffle, Repeat, Next, Previous and every queue edit waited until
  /// the listener paused. Playback starting is reported by the player's
  /// own state events; a failure, whenever it comes, is reported here.
  void _startPlaying() {
    unawaited(
      _audioPlayer.play().then<void>(
        (_) {},
        onError: (Object error) {
          if (!_disposed) _emitFailure(error);
        },
      ),
    );
  }

  /// Whether the paused position was set by a seek, as a restored session
  /// is, rather than by pausing playback. Cleared when playback starts.
  bool _pausedAtSeekedPosition = false;

  /// A finished queue, or a restored one paused at its very end. Play then
  /// replays the final song (SN50-R4) instead of doing nothing.
  bool get _isAtEndOfQueue {
    if (_state.status == PlaybackStatus.completed) return true;

    final duration = _state.duration;
    if (_state.isPlaying || _audioPlayer.hasNext || duration <= Duration.zero) {
      return false;
    }

    // A restored end can fall a little short of the duration. A pause in
    // the last second of playback is not the end: Play resumes there.
    final end = _pausedAtSeekedPosition && duration > const Duration(seconds: 2)
        ? duration - const Duration(seconds: 1)
        : duration;
    return _state.position >= end;
  }

  /// just_audio keeps `playing` set after completion, so its play() would
  /// return at once. Clearing it first makes play() start the song again.
  Future<void> _replayFinalSong() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    }

    await _seekPlayer(Duration.zero);
    _startPlaying();
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
      _pausedAtSeekedPosition = !_state.isPlaying;
      await _seekPlayer(clamped);
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> skipNext() {
    return _inTurn(_skipNext);
  }

  Future<void> _skipNext() async {
    _ensureNotDisposed();

    // Repeat One repeats a song that finishes on its own; an explicit Next
    // moves on to the next entry and Repeat One stays on for it.
    final repeatOneTarget = _state.repeatMode == PlaybackRepeatMode.one
        ? _audioPlayer.adjacentIndex(1)
        : null;
    final canAdvance = _state.repeatMode == PlaybackRepeatMode.one
        ? repeatOneTarget != null
        : _audioPlayer.hasNext;

    if (canAdvance) {
      _pendingTransitionCause = PlaybackTransitionCause.skipNext;
    }

    try {
      if (repeatOneTarget != null) {
        await _seekPlayer(Duration.zero, index: repeatOneTarget);
      } else if (_state.repeatMode != PlaybackRepeatMode.one) {
        await _audioPlayer.seekToNext();
      }
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
  Future<void> skipPrevious() {
    return _inTurn(_skipPrevious);
  }

  Future<void> _skipPrevious() async {
    _ensureNotDisposed();

    if (_state.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    // Under Repeat One, Previous goes to the previous entry, as it does
    // without it; the player alone would only restart the current song.
    final repeatOneTarget = _state.repeatMode == PlaybackRepeatMode.one
        ? _audioPlayer.adjacentIndex(-1)
        : null;
    final canGoBack = _state.repeatMode == PlaybackRepeatMode.one
        ? repeatOneTarget != null
        : _audioPlayer.hasPrevious;

    if (!canGoBack) {
      await seek(Duration.zero);
      return;
    }

    _pendingTransitionCause = PlaybackTransitionCause.skipPrevious;

    try {
      if (repeatOneTarget != null) {
        await _seekPlayer(Duration.zero, index: repeatOneTarget);
      } else {
        await _audioPlayer.seekToPrevious();
      }
    } catch (error) {
      if (_pendingTransitionCause == PlaybackTransitionCause.skipPrevious) {
        _pendingTransitionCause = null;
      }

      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> skipToIndex(int index) {
    return _inTurn(() => _skipToIndex(index));
  }

  Future<void> _skipToIndex(int index) async {
    _ensureNotDisposed();

    if (index < 0 || index >= _state.queue.length) {
      throw RangeError.index(index, _state.queue.tracks, 'index');
    }

    final changesTrack = index != _state.queue.currentIndex;

    if (changesTrack) {
      _pendingTransitionCause = PlaybackTransitionCause.skipToIndex;
    }

    try {
      // Shuffled, the chosen entry plays next in the cycle: whatever has
      // played stays played, and nothing upcoming is skipped.
      final order = shuffleOrder;
      if (changesTrack && order != null && _state.queue.hasCurrentTrack) {
        _shuffleOrder?.arrange(
          orderPlayingNext(
            order,
            current: _state.queue.currentIndex,
            target: index,
          ),
        );
        await _audioPlayer.shuffle();
      }
      await _seekPlayer(Duration.zero, index: index);
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
  Future<void> insertTrack(PlaybackTrack track, {required int index}) {
    return _inTurn(() => _insertTrack(track, index: () => index));
  }

  /// [index] is read when the insert runs, after any command before it, so
  /// an append always goes after everything already added.
  Future<void> _insertTrack(
    PlaybackTrack track, {
    required int Function() index,
  }) async {
    _ensureNotDisposed();

    if (!track.hasPlayablePath || track.isBlocked) {
      throw ArgumentError.value(
        track.songId,
        'track',
        'Playback track is unavailable or blocked.',
      );
    }

    final at = index();
    if (at < 0 || at > _state.queue.length) {
      throw RangeError.range(at, 0, _state.queue.length, 'index');
    }

    final updatedQueue = _state.queue.insertTrack(track, index: at);

    try {
      await _changeSources(
        () => _audioPlayer.insertAudioSource(at, _audioSourceFor(track)),
      );

      _emit(
        _state.copyWith(
          queue: _withCurrentDisplay(updatedQueue),
          clearError: true,
        ),
      );
      _reconcileIndexAfterQueueChange();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  /// Runs a change to the player's sources with its index events held back
  /// (see [_changingQueue]).
  Future<void> _changeSources(Future<void> Function() change) async {
    _changingQueue = true;
    _indexDuringQueueChange = null;
    try {
      await change();
    } finally {
      _changingQueue = false;
    }
  }

  /// After a queue change: if the player moved to a different entry while
  /// the change was in flight (the song ended and the next one began),
  /// that is a real song change and the queue follows it. An index that
  /// only reflects the shift is the entry already current, so nothing is
  /// reported.
  void _reconcileIndexAfterQueueChange() {
    final index = _indexDuringQueueChange;
    _indexDuringQueueChange = null;
    if (index != null) _handleCurrentIndexChanged(index);
  }

  /// [queue], built before an await on the player, with the display
  /// fields the queue has now: a credit or title refresh that arrived
  /// meanwhile is kept, never overwritten by the older copy.
  PlaybackQueue _withCurrentDisplay(PlaybackQueue queue) =>
      queue.withTrackDisplay(_state.queue.tracks);

  @override
  bool refreshTrackDisplay(Iterable<PlaybackTrack> tracks) {
    if (_disposed) {
      return false;
    }

    final updatedQueue = _state.queue.withTrackDisplay(tracks);

    if (identical(updatedQueue, _state.queue)) {
      return false;
    }

    _emit(_state.copyWith(queue: updatedQueue));
    return true;
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) {
    // The end of the queue as it is when this append runs, after anything
    // added before it.
    return _inTurn(() => _insertTrack(track, index: () => _state.queue.length));
  }

  @override
  Future<void> removeTrackAt(int index) {
    return _inTurn(() => _removeTrackAt(index));
  }

  Future<void> _removeTrackAt(int index) async {
    _ensureNotDisposed();

    if (index < 0 || index >= _state.queue.length) {
      throw RangeError.index(index, _state.queue.tracks, 'index');
    }

    final updatedQueue = _state.queue.removeTrackAt(index);
    // Removing the playing entry makes the next one current, from its
    // start; it never inherits the removed song's position (which made the
    // next song look as if it had just finished and restarted).
    final removesCurrent = index == _state.queue.currentIndex;

    try {
      await _changeSources(() => _audioPlayer.removeAudioSourceAt(index));

      _emit(
        _state.copyWith(
          queue: _withCurrentDisplay(updatedQueue),
          position: updatedQueue.isEmpty || removesCurrent
              ? Duration.zero
              : _state.position,
          duration: updatedQueue.currentTrack?.duration ?? Duration.zero,
          clearError: true,
        ),
      );
      _reconcileIndexAfterQueueChange();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) {
    return _inTurn(() => _moveTrack(oldIndex: oldIndex, newIndex: newIndex));
  }

  Future<void> _moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {
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
      // A moved entry keeps its place in the shuffled play order.
      _shuffleOrder?.beginMove();
      await _changeSources(
        () => _audioPlayer.moveAudioSource(oldIndex, newIndex),
      );

      _emit(
        _state.copyWith(
          queue: _withCurrentDisplay(updatedQueue),
          clearError: true,
        ),
      );
      _reconcileIndexAfterQueueChange();
    } catch (error) {
      _emitFailure(error);
      rethrow;
    }
  }

  /// The play order of the loaded queue (SN-50 device QA).
  SonusShuffleOrder? _shuffleOrder;

  @override
  Future<void> setShuffleEnabled(bool enabled) {
    return _inTurn(() => _setShuffleEnabled(enabled));
  }

  Future<void> _setShuffleEnabled(bool enabled) async {
    _ensureNotDisposed();

    try {
      // BUG-06: shuffle that is already on stays as it is. Shuffling again
      // would deal the songs already played back into the cycle.
      if (enabled && !_state.shuffleEnabled) {
        // Turning shuffle on keeps the entries already played (before the
        // current one in queue order) first; only the rest are shuffled.
        final queue = _state.queue;
        if (queue.hasCurrentTrack) {
          _shuffleOrder?.arrange(
            orderKeepingPlayed(queue.length, current: queue.currentIndex),
          );
        }
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
  Future<void> setRepeatMode(PlaybackRepeatMode mode) {
    return _inTurn(() => _setRepeatMode(mode));
  }

  Future<void> _setRepeatMode(PlaybackRepeatMode mode) async {
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

    // just_audio keeps the position and the loaded sources through stop(),
    // and Play resumes from there. Report the same, or the player shows
    // 0:00 with seeking disabled and a restart restores the wrong position.
    _emit(
      PlaybackState(
        queue: _state.queue,
        status: PlaybackStatus.idle,
        position: _state.position,
        duration: _state.duration,
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

  /// Seeks Sonus asked for that the player has not finished, and whether
  /// the first position after the last one is still to come (BUG-11
  /// hardening). Position jumps they cause are seeks, never the song
  /// starting over.
  int _seeksInFlight = 0;
  bool _seekLanding = false;

  /// The smallest backward jump that is taken as the song starting over.
  static const _loopJump = Duration(seconds: 1);

  Future<void> _seekPlayer(Duration position, {int? index}) async {
    _seeksInFlight++;
    try {
      await _audioPlayer.seek(position, index: index);
    } finally {
      _seeksInFlight--;
      _seekLanding = true;
    }
  }

  /// Whether the playing entry starts over by itself when it ends: Repeat
  /// One, or Repeat All over a single entry.
  bool get _repeatsCurrentEntry =>
      _state.repeatMode == PlaybackRepeatMode.one ||
      (_state.repeatMode == PlaybackRepeatMode.all && _state.queue.length == 1);

  void _handlePositionChanged(Duration position) {
    if (_disposed) {
      return;
    }

    if (_seeksInFlight > 0 || _seekLanding) {
      // The seek arriving: the first position after it is where it went.
      if (_seeksInFlight == 0) _seekLanding = false;
    } else if (_repeatsCurrentEntry &&
        _state.isPlaying &&
        position + _loopJump < _state.position) {
      // The song played to its end and started over (Repeat One), with no
      // seek asked for: a new play of it, whatever position updates came
      // before (they are sparse in the background).
      _emit(
        _state.copyWith(
          position: position,
          transitionCause: PlaybackTransitionCause.repeated,
        ),
      );
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
    if (_disposed || index == null) {
      return;
    }

    // Mid-change, the index may be in the old queue's numbering or the
    // new one's; only the last is meaningful, once the change is done.
    if (_changingQueue) {
      _indexDuringQueueChange = index;
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

    // A failed source leaves the player idle. Reporting that as an ordinary
    // idle would erase the failure and playback would end silently; Stop
    // and loading a queue still replace it.
    if (status == PlaybackStatus.idle &&
        _state.status == PlaybackStatus.failed) {
      return;
    }

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
    // Song id and error type only: messages can contain file paths.
    developer.log(
      'Playback failed. song=${_state.queue.currentTrack?.songId} '
      'error=${error.runtimeType}'
      '${error is PlayerException ? ' code=${error.code}' : ''}',
      name: 'sonus.playback',
      level: 900,
    );

    _emit(
      _state.copyWith(
        status: PlaybackStatus.failed,
        errorMessage: error.toString(),
        clearTransitionCause: true,
      ),
    );
  }

  void _emit(PlaybackState state) {
    // Every state carries the player's own answer for Next and Previous,
    // so the controls follow shuffle order and repeat all.
    _state = state.copyWith(
      nextAvailable: state.hasTrack && _audioPlayer.hasNext,
      previousAvailable: state.hasTrack && _audioPlayer.hasPrevious,
    );

    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Playback engine has been disposed.');
    }
  }
}
