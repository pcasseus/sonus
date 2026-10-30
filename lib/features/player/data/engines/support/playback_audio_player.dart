import 'package:just_audio/just_audio.dart';

abstract interface class PlaybackAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<int?> get currentIndexStream;
  Stream<PlayerState> get playerStateStream;
  Stream<PlayerException> get errorStream;

  bool get hasPrevious;
  bool get hasNext;

  /// The entry [offset] steps from the current one in play order (shuffle
  /// included), as if Repeat One were off: Repeat All still wraps. Null at
  /// the queue's edge. Lets an explicit Next or Previous move on under
  /// Repeat One, which only repeats a song that finishes on its own.
  int? adjacentIndex(int offset);

  /// Whether the player intends to play. Like just_audio, this survives
  /// source changes and completion until [pause] or [stop].
  bool get playing;

  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
    ShuffleOrder? shuffleOrder,
  });

  /// The shuffled play order (queue indices). Only meaningful while
  /// shuffle mode is on.
  List<int> get shuffleIndices;

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
  List<int> get shuffleIndices => List.of(_audioPlayer.shuffleIndices);

  @override
  int? adjacentIndex(int offset) {
    final current = _audioPlayer.currentIndex;
    final order = _audioPlayer.effectiveIndices;
    if (current == null || order.isEmpty) return null;

    final position = order.indexOf(current);
    if (position < 0) return null;

    final target = position + offset;
    if (_audioPlayer.loopMode == LoopMode.all) {
      return order[target % order.length];
    }
    if (target < 0 || target >= order.length) return null;
    return order[target];
  }

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
    ShuffleOrder? shuffleOrder,
  }) {
    return _audioPlayer.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
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

/// A shuffle order that starts from a saved permutation (SN-50 #24): the
/// first fill lays the saved indices down exactly; later inserts, removals
/// and an explicit reshuffle behave like [DefaultShuffleOrder].
class RestoredShuffleOrder extends DefaultShuffleOrder {
  RestoredShuffleOrder(List<int> saved) : _saved = List.of(saved);

  List<int>? _saved;

  @override
  void insert(int index, int count) {
    final saved = _saved;
    if (saved != null && indices.isEmpty && index == 0) {
      _saved = null;
      if (count == saved.length) {
        indices.addAll(saved);
        return;
      }
    }
    super.insert(index, count);
  }
}
