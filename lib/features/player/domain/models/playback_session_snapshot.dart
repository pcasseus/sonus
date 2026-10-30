import 'package:flutter/foundation.dart';

/// The queue and position to bring back after Sonus restarts.
///
/// Only song identities are stored; tracks are re-read from the library
/// and re-checked for playability when restored.
@immutable
class PlaybackSessionSnapshot {
  const PlaybackSessionSnapshot({
    required this.songIds,
    required this.currentIndex,
    required this.position,
    this.shuffleOrder,
  });

  static const int version = 1;

  final List<String> songIds;
  final int currentIndex;
  final Duration position;

  /// The shuffled play order (indices into [songIds]) when shuffle was on
  /// (SN-50 #24). Optional within version 1: older builds ignore it, and an
  /// unusable value is dropped without losing the session.
  final List<int>? shuffleOrder;

  Map<String, Object> toJson() => {
    'version': version,
    'songIds': songIds,
    'currentIndex': currentIndex,
    'positionMs': position.inMilliseconds,
    'shuffleOrder': ?shuffleOrder,
  };

  /// Null when [json] is not a usable snapshot.
  static PlaybackSessionSnapshot? fromJson(Map<String, Object?> json) {
    if (json['version'] != version) return null;

    final ids = json['songIds'];
    final index = json['currentIndex'];
    final positionMs = json['positionMs'];

    if (ids is! List ||
        ids.isEmpty ||
        ids.any((id) => id is! String || id.isEmpty) ||
        index is! int ||
        index < 0 ||
        index >= ids.length ||
        positionMs is! int ||
        positionMs < 0) {
      return null;
    }

    return PlaybackSessionSnapshot(
      songIds: List.unmodifiable(ids.cast<String>()),
      currentIndex: index,
      position: Duration(milliseconds: positionMs),
      shuffleOrder: _shuffleOrderFrom(json['shuffleOrder'], ids.length),
    );
  }

  /// A permutation of the queue's indices, or null.
  static List<int>? _shuffleOrderFrom(Object? value, int length) {
    if (value is! List || value.length != length) return null;
    final seen = <int>{};
    for (final index in value) {
      if (index is! int || index < 0 || index >= length || !seen.add(index)) {
        return null;
      }
    }
    return List.unmodifiable(value.cast<int>());
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackSessionSnapshot &&
      listEquals(other.songIds, songIds) &&
      other.currentIndex == currentIndex &&
      other.position == position &&
      listEquals(other.shuffleOrder, shuffleOrder);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(songIds),
    currentIndex,
    position,
    shuffleOrder == null ? null : Object.hashAll(shuffleOrder!),
  );
}
