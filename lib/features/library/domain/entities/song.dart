class Song {
  static const Object _unset = Object();

  const Song({
    required this.id,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
    required this.title,
    required this.canonicalTitle,
    required this.trackNumber,
    this.discNumber = 1,
    required this.durationSeconds,
    required this.isSingle,
    required this.createdAt,
    required this.updatedAt,
    this.featuredArtists = const [],
    this.artworkId,
  });

  final String id;
  final String artistId;
  final String albumId;
  final String albumEditionId;
  final String title;
  final String canonicalTitle;
  final int trackNumber;
  final int discNumber;
  final int durationSeconds;
  final bool isSingle;
  final List<String> featuredArtists;
  final String? artworkId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Song copyWith({
    String? id,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? title,
    String? canonicalTitle,
    int? trackNumber,
    int? discNumber,
    int? durationSeconds,
    bool? isSingle,
    List<String>? featuredArtists,
    Object? artworkId = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Song(
      id: id ?? this.id,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumEditionId: albumEditionId ?? this.albumEditionId,
      title: title ?? this.title,
      canonicalTitle: canonicalTitle ?? this.canonicalTitle,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isSingle: isSingle ?? this.isSingle,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      artworkId: identical(artworkId, _unset)
          ? this.artworkId
          : artworkId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Song && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
