enum PlaybackSessionEndReason {
  completed,
  skipped,
  stopped,
  replaced,
  interrupted,
  failed,
}

class PlaybackSession {
  static const Object _unset = Object();

  const PlaybackSession({
    required this.id,
    required this.songId,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
    required this.songTitle,
    required this.artistName,
    required this.albumTitle,
    required this.albumEditionTitle,
    required this.startedAt,
    required this.listenedDuration,
    required this.trackDuration,
    required this.finalPosition,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.endedAt,
    this.endReason,
    this.sourceContext,
  });

  final String id;
  final String? userId;

  final String songId;
  final String artistId;
  final String albumId;
  final String albumEditionId;

  final String songTitle;
  final String artistName;
  final String albumTitle;
  final String albumEditionTitle;

  final DateTime startedAt;
  final DateTime? endedAt;

  final Duration listenedDuration;
  final Duration trackDuration;
  final Duration finalPosition;

  final PlaybackSessionEndReason? endReason;
  final String? sourceContext;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEnded => endedAt != null;

  PlaybackSession copyWith({
    String? id,
    Object? userId = _unset,
    String? songId,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? songTitle,
    String? artistName,
    String? albumTitle,
    String? albumEditionTitle,
    DateTime? startedAt,
    Object? endedAt = _unset,
    Duration? listenedDuration,
    Duration? trackDuration,
    Duration? finalPosition,
    Object? endReason = _unset,
    Object? sourceContext = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlaybackSession(
      id: id ?? this.id,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      songId: songId ?? this.songId,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumEditionId: albumEditionId ?? this.albumEditionId,
      songTitle: songTitle ?? this.songTitle,
      artistName: artistName ?? this.artistName,
      albumTitle: albumTitle ?? this.albumTitle,
      albumEditionTitle: albumEditionTitle ?? this.albumEditionTitle,
      startedAt: startedAt ?? this.startedAt,
      endedAt: identical(endedAt, _unset) ? this.endedAt : endedAt as DateTime?,
      listenedDuration: listenedDuration ?? this.listenedDuration,
      trackDuration: trackDuration ?? this.trackDuration,
      finalPosition: finalPosition ?? this.finalPosition,
      endReason: identical(endReason, _unset)
          ? this.endReason
          : endReason as PlaybackSessionEndReason?,
      sourceContext: identical(sourceContext, _unset)
          ? this.sourceContext
          : sourceContext as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is PlaybackSession && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
