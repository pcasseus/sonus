class AlbumEditionTrack {
  const AlbumEditionTrack({
    required this.albumEditionId,
    required this.songId,
    required this.discNumber,
    required this.trackNumber,
    required this.sortPosition,
    required this.createdAt,
    required this.updatedAt,
  });

  final String albumEditionId;
  final String songId;
  final int discNumber;
  final int trackNumber;
  final int sortPosition;
  final DateTime createdAt;
  final DateTime updatedAt;

  AlbumEditionTrack copyWith({
    int? discNumber,
    int? trackNumber,
    int? sortPosition,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlbumEditionTrack(
      albumEditionId: albumEditionId,
      songId: songId,
      discNumber: discNumber ?? this.discNumber,
      trackNumber: trackNumber ?? this.trackNumber,
      sortPosition: sortPosition ?? this.sortPosition,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AlbumEditionTrack &&
            other.albumEditionId == albumEditionId &&
            other.songId == songId;
  }

  @override
  int get hashCode => Object.hash(albumEditionId, songId);
}
