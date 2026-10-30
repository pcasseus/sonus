import '../models/playback_track.dart';

/// An engine that can report and restore its exact shuffled play order
/// (SN-50 #24). Optional: engines without it keep the earlier behaviour,
/// where a restored queue is shuffled afresh.
abstract interface class ShuffleOrderPlayback {
  /// The play order as queue indices while shuffle is on, otherwise null.
  List<int>? get shuffleOrder;

  /// Loads [tracks] like `PlaybackEngine.loadQueue`, playing them in
  /// [shuffleOrder] (a permutation of their indices) while shuffle is on.
  Future<void> loadQueueInShuffleOrder(
    List<PlaybackTrack> tracks, {
    required List<int> shuffleOrder,
    int startIndex = 0,
    bool autoPlay = false,
  });
}

/// Whether [order] lists each index of a queue of [length] exactly once.
bool isShuffleOrderFor(List<int> order, int length) {
  if (order.length != length) return false;
  final seen = <int>{};
  for (final index in order) {
    if (index < 0 || index >= length || !seen.add(index)) return false;
  }
  return true;
}
