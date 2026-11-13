import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:sonus_next/features/player/data/engines/support/playback_audio_player.dart';

/// A [PlaybackAudioPlayer] that follows just_audio's state rules closely
/// enough to expose engine status bugs:
///
/// * `playing` is the listener's intent and survives source changes and
///   completion; it is only cleared by [pause] and [stop].
/// * [play] while already playing, and [pause] while paused, emit nothing.
/// * Loading sources reports loading, then ready, before the returned
///   future completes.
/// * Audio is only heard while [playing] and ready.
/// * Seeking a completed source makes it ready again.
/// * [play] returns a Future that stays pending while playback goes on.
///   As just_audio documents, and as its Android player does, it completes
///   only when playback is paused or stopped, the queue reaches its end,
///   another play request replaces it, or the player is disposed (BUG-11).
///   Already playing, or at the end of the queue, it completes at once.
class SimulatedJustAudioPlayer implements PlaybackAudioPlayer {
  /// With [modelShuffle], shuffle mode plays in a real shuffle order, as
  /// just_audio does: a seeded [DefaultShuffleOrder], or the order given
  /// to [setAudioSources]. Off by default, so shuffle does not change the
  /// play order for tests written before it was modelled.
  SimulatedJustAudioPlayer({this.modelShuffle = false});

  final bool modelShuffle;
  ShuffleOrder _shuffleOrder = DefaultShuffleOrder(random: Random(7));
  bool _shuffleEnabled = false;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durations =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<int?> _indexes = StreamController<int?>.broadcast(
    sync: true,
  );
  final StreamController<PlayerState> _playerStates =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<PlayerException> _errors =
      StreamController<PlayerException>.broadcast(sync: true);

  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  int? _index;
  int _length = 0;
  LoopMode _loopMode = LoopMode.off;
  Duration _position = Duration.zero;

  @override
  bool get playing => _playing;

  ProcessingState get processingState => _processing;

  /// Whether sound is coming out of the speaker.
  bool get audible => _playing && _processing == ProcessingState.ready;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<int?> get currentIndexStream => _indexes.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<PlayerException> get errorStream => _errors.stream;

  // Like just_audio: repeat all wraps around the queue, and under repeat
  // one the next and previous items are the current one.
  @override
  bool get hasPrevious => _relative(-1, repeatOne: true) != null;

  @override
  bool get hasNext => _relative(1, repeatOne: true) != null;

  @override
  int? adjacentIndex(int offset) => _relative(offset, repeatOne: false);

  int? _relative(int offset, {required bool repeatOne}) {
    final index = _index;
    if (_length == 0 || index == null) return null;
    if (repeatOne && _loopMode == LoopMode.one) return index;
    final order = _playOrder;
    final position = order.indexOf(index);
    if (position < 0) return null;
    final target = position + offset;
    if (_loopMode == LoopMode.all) return order[target % order.length];
    if (target < 0 || target >= order.length) return null;
    return order[target];
  }

  List<int> get _playOrder => modelShuffle && _shuffleEnabled
      ? _shuffleOrder.indices
      : [for (var i = 0; i < _length; i++) i];

  @override
  List<int> get shuffleIndices => List.of(_shuffleOrder.indices);

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    _length = sources.length;
    _shuffleOrder = shuffleOrder ?? DefaultShuffleOrder(random: Random(7));
    _shuffleOrder.clear();
    _shuffleOrder.insert(0, sources.length);
    // just_audio shuffles every source it loads, the start first.
    _shuffleOrder.shuffle(initialIndex: initialIndex);
    _setProcessing(ProcessingState.loading);
    _index = initialIndex;
    _indexes.add(initialIndex);
    await Future<void>.delayed(Duration.zero);
    _setProcessing(ProcessingState.ready);
    return const Duration(minutes: 3);
  }

  /// The pending result of the last play request (see the class notes).
  Completer<void>? _playResult;

  /// Whether a play request is still pending: playback was asked for and
  /// has not paused, stopped or ended since.
  bool get playRequestPending => _playResult != null;

  /// How many sources the player holds, to compare with the engine's queue.
  int get sourceCountForTest => _length;

  @override
  Future<void> play() {
    if (_playing) {
      return Future<void>.value();
    }

    _playing = true;

    // A newer request answers the one before it, as on Android.
    _settlePlay();
    final result = _playResult = Completer<void>();

    // After stop(), just_audio prepares the same sources again and
    // resumes from the retained position.
    if (_processing == ProcessingState.idle && _length > 0) {
      _setProcessing(ProcessingState.loading);
      _setProcessing(ProcessingState.ready);
      _positions.add(_position);
    } else {
      _emitState();
    }

    if (_processing == ProcessingState.completed) _settlePlay();
    return result.future;
  }

  void _settlePlay() {
    final result = _playResult;
    _playResult = null;
    if (result != null && !result.isCompleted) result.complete();
  }

  @override
  Future<void> pause() async {
    if (!_playing) {
      return;
    }

    _playing = false;
    _emitState();
    _settlePlay();
  }

  /// Like just_audio, stop() releases the decoder but keeps the position.
  @override
  Future<void> stop() async {
    _playing = false;
    _processing = ProcessingState.idle;
    _emitState();
    _settlePlay();
  }

  /// Playback reached [position] (the platform's position updates).
  void advanceTo(Duration position) {
    _position = position;
    _positions.add(position);
  }

  /// The last source finished. just_audio leaves `playing` set, and the
  /// pending play request completes.
  void complete() {
    _setProcessing(ProcessingState.completed);
    _settlePlay();
  }

  /// The current source cannot be read (for example its file was moved).
  /// just_audio reports the error and an idle player from the same event,
  /// through two streams, so either may arrive first.
  void failSource({bool errorFirst = true}) {
    final error = PlayerException(0, 'Source error', _index);

    if (errorFirst) {
      _errors.add(error);
      _setProcessing(ProcessingState.idle);
    } else {
      _setProcessing(ProcessingState.idle);
      _errors.add(error);
    }
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    if (index != null) {
      _index = index;
      _indexes.add(index);
    }
    _position = position;
    _positions.add(position);

    // Seeking a completed source prepares it again, like just_audio.
    if (_processing == ProcessingState.completed) {
      _setProcessing(ProcessingState.ready);
    }
  }

  @override
  Future<void> seekToNext() async {
    final next = _relative(1, repeatOne: true);
    if (next != null) await seek(Duration.zero, index: next);
  }

  @override
  Future<void> seekToPrevious() async {
    final previous = _relative(-1, repeatOne: true);
    if (previous != null) await seek(Duration.zero, index: previous);
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async {
    _length++;
    _shuffleOrder.insert(index, 1);
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    _length--;
    _shuffleOrder.removeRange(index, index + 1);
    // Like just_audio, removing an earlier item keeps the current one
    // playing at its new index.
    final current = _index;
    if (current != null && index < current) {
      _index = current - 1;
      _indexes.add(_index);
    }
    // Removing the playing source moves on to the next one, from its start.
    // The platform reports that position later, after the removal returns.
    if (current != null && index == current) {
      _position = Duration.zero;
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          if (!_positions.isClosed) _positions.add(_position);
        }),
      );
    }
  }

  @override
  Future<void> moveAudioSource(int oldIndex, int newIndex) async {
    _shuffleOrder
      ..removeRange(oldIndex, oldIndex + 1)
      ..insert(newIndex, 1);
    final current = _index;
    if (current == null) return;
    final moved = current == oldIndex
        ? newIndex
        : oldIndex < current && current <= newIndex
        ? current - 1
        : newIndex <= current && current < oldIndex
        ? current + 1
        : current;
    if (moved != current) {
      _index = moved;
      _indexes.add(moved);
    }
  }

  @override
  Future<void> shuffle() async => _shuffleOrder.shuffle(initialIndex: _index);

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

  @override
  Future<void> dispose() async {
    _settlePlay();
    await _positions.close();
    await _durations.close();
    await _indexes.close();
    await _playerStates.close();
    await _errors.close();
  }

  void _setProcessing(ProcessingState state) {
    _processing = state;
    _emitState();
  }

  void _emitState() => _playerStates.add(PlayerState(_playing, _processing));
}
