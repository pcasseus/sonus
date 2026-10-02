enum AlbumEditionTrackAuthority { inferred, manual }

class AlbumEditionTrack {
  const AlbumEditionTrack({
    required this.albumEditionId,
    required this.songId,
    required this.discNumber,
    required this.trackNumber,
    required this.sortPosition,
    this.numberingAuthority = AlbumEditionTrackAuthority.inferred,
    this.orderingAuthority = AlbumEditionTrackAuthority.inferred,
    required this.createdAt,
    required this.updatedAt,
  });

  final String albumEditionId;
  final String songId;
  final int discNumber;
  final int trackNumber;
  final int sortPosition;
  final AlbumEditionTrackAuthority numberingAuthority;
  final AlbumEditionTrackAuthority orderingAuthority;
  final DateTime createdAt;
  final DateTime updatedAt;

  AlbumEditionTrack copyWith({
    int? discNumber,
    int? trackNumber,
    int? sortPosition,
    AlbumEditionTrackAuthority? numberingAuthority,
    AlbumEditionTrackAuthority? orderingAuthority,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlbumEditionTrack(
      albumEditionId: albumEditionId,
      songId: songId,
      discNumber: discNumber ?? this.discNumber,
      trackNumber: trackNumber ?? this.trackNumber,
      sortPosition: sortPosition ?? this.sortPosition,
      numberingAuthority: numberingAuthority ?? this.numberingAuthority,
      orderingAuthority: orderingAuthority ?? this.orderingAuthority,
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
