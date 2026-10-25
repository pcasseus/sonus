import 'package:just_audio/just_audio.dart';

abstract interface class PlaybackAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<int?> get currentIndexStream;
  Stream<PlayerState> get playerStateStream;
  Stream<PlayerException> get errorStream;

  bool get hasPrevious;
  bool get hasNext;

  /// Whether the player intends to play. Like just_audio, this survives
  /// source changes and completion until [pause] or [stop].
  bool get playing;

  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
  });

  Future<void> play();
  Future<void> pause();

  Future<void> seek(Duration position, {int? index});

  Future<void> seekToNext();
  Future<void> seekToPrevious();

  Future<void> insertAudioSource(int index, AudioSource source);
  Future<void> removeAudioSourceAt(int index);
  Future<void> moveAudioSource(int oldIndex, int newIndex);

  Future<void> shuffle();
  Future<void> setShuffleModeEnabled(bool enabled);
  Future<void> setLoopMode(LoopMode mode);

  Future<void> stop();
  Future<void> dispose();
}

class JustAudioPlayerAdapter implements PlaybackAudioPlayer {
  JustAudioPlayerAdapter({AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer();

  final AudioPlayer _audioPlayer;

  @override
  Stream<Duration> get positionStream => _audioPlayer.positionStream;

  @override
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  @override
  Stream<int?> get currentIndexStream => _audioPlayer.currentIndexStream;

  @override
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;

  @override
  Stream<PlayerException> get errorStream => _audioPlayer.errorStream;

  @override
  bool get hasPrevious => _audioPlayer.hasPrevious;

  @override
  bool get hasNext => _audioPlayer.hasNext;

  @override
  bool get playing => _audioPlayer.playing;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
  }) {
    return _audioPlayer.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> play() => _audioPlayer.play();

  @override
  Future<void> pause() => _audioPlayer.pause();

  @override
  Future<void> seek(Duration position, {int? index}) {
    return _audioPlayer.seek(position, index: index);
  }

  @override
  Future<void> seekToNext() => _audioPlayer.seekToNext();

  @override
  Future<void> seekToPrevious() => _audioPlayer.seekToPrevious();

  @override
  Future<void> insertAudioSource(int index, AudioSource source) {
    return _audioPlayer.insertAudioSource(index, source);
  }

  @override
  Future<void> removeAudioSourceAt(int index) {
    return _audioPlayer.removeAudioSourceAt(index);
  }

  @override
  Future<void> moveAudioSource(int oldIndex, int newIndex) {
    return _audioPlayer.moveAudioSource(oldIndex, newIndex);
  }

  @override
  Future<void> shuffle() => _audioPlayer.shuffle();

  @override
  Future<void> setShuffleModeEnabled(bool enabled) {
    return _audioPlayer.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) {
    return _audioPlayer.setLoopMode(mode);
  }

  @override
  Future<void> stop() => _audioPlayer.stop();

  @override
  Future<void> dispose() => _audioPlayer.dispose();
}
