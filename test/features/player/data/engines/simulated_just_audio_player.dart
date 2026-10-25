import 'dart:async';

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
class SimulatedJustAudioPlayer implements PlaybackAudioPlayer {
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

  // Like just_audio, repeat all wraps around the queue.
  @override
  bool get hasPrevious =>
      _length > 0 && (_loopMode == LoopMode.all || (_index ?? 0) > 0);

  @override
  bool get hasNext =>
      _length > 0 && (_loopMode == LoopMode.all || (_index ?? 0) < _length - 1);

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    _length = sources.length;
    _setProcessing(ProcessingState.loading);
    _index = initialIndex;
    _indexes.add(initialIndex);
    await Future<void>.delayed(Duration.zero);
    _setProcessing(ProcessingState.ready);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    if (_playing) {
      return;
    }

    _playing = true;

    // After stop(), just_audio prepares the same sources again and
    // resumes from the retained position.
    if (_processing == ProcessingState.idle && _length > 0) {
      _setProcessing(ProcessingState.loading);
      _setProcessing(ProcessingState.ready);
      _positions.add(_position);
      return;
    }

    _emitState();
  }

  @override
  Future<void> pause() async {
    if (!_playing) {
      return;
    }

    _playing = false;
    _emitState();
  }

  /// Like just_audio, stop() releases the decoder but keeps the position.
  @override
  Future<void> stop() async {
    _playing = false;
    _processing = ProcessingState.idle;
    _emitState();
  }

  /// Playback reached [position] (the platform's position updates).
  void advanceTo(Duration position) {
    _position = position;
    _positions.add(position);
  }

  /// The last source finished. just_audio leaves `playing` set.
  void complete() => _setProcessing(ProcessingState.completed);

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
  }

  @override
  Future<void> seekToNext() async {
    if (hasNext) {
      await seek(Duration.zero, index: (_index ?? 0) + 1);
    }
  }

  @override
  Future<void> seekToPrevious() async {
    if (hasPrevious) {
      await seek(Duration.zero, index: (_index ?? 0) - 1);
    }
  }

  @override
  Future<void> insertAudioSource(int index, AudioSource source) async {
    _length++;
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    _length--;
  }

  @override
  Future<void> moveAudioSource(int oldIndex, int newIndex) async {}

  @override
  Future<void> shuffle() async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

  @override
  Future<void> dispose() async {
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
