class QualifiedPlay {
  static const Object _unset = Object();

  const QualifiedPlay({
    required this.id,
    required this.playbackSessionId,
    required this.songId,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
    required this.qualifiedAt,
    required this.listenedDuration,
    required this.trackDuration,
    required this.createdAt,
    this.userId,
  });

  final String id;
  final String playbackSessionId;
  final String? userId;

  final String songId;
  final String artistId;
  final String albumId;
  final String albumEditionId;

  final DateTime qualifiedAt;

  final Duration listenedDuration;
  final Duration trackDuration;

  final DateTime createdAt;

  QualifiedPlay copyWith({
    String? id,
    String? playbackSessionId,
    Object? userId = _unset,
    String? songId,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? qualifiedAt,
    Duration? listenedDuration,
    Duration? trackDuration,
    DateTime? createdAt,
  }) {
    return QualifiedPlay(
      id: id ?? this.id,
      playbackSessionId: playbackSessionId ?? this.playbackSessionId,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      songId: songId ?? this.songId,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumEditionId: albumEditionId ?? this.albumEditionId,
      qualifiedAt: qualifiedAt ?? this.qualifiedAt,
      listenedDuration: listenedDuration ?? this.listenedDuration,
      trackDuration: trackDuration ?? this.trackDuration,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is QualifiedPlay && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
