class PlaybackListeningSegment {
  static const Object _unset = Object();

  const PlaybackListeningSegment({
    required this.id,
    required this.playbackSessionId,
    required this.startedAt,
    required this.listenedDuration,
    required this.createdAt,
    required this.updatedAt,
    this.endedAt,
  });

  final String id;
  final String playbackSessionId;

  final DateTime startedAt;
  final DateTime? endedAt;

  final Duration listenedDuration;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEnded => endedAt != null;

  PlaybackListeningSegment copyWith({
    String? id,
    String? playbackSessionId,
    DateTime? startedAt,
    Object? endedAt = _unset,
    Duration? listenedDuration,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlaybackListeningSegment(
      id: id ?? this.id,
      playbackSessionId: playbackSessionId ?? this.playbackSessionId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
      listenedDuration: listenedDuration ?? this.listenedDuration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackListeningSegment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
