enum AlbumEditionType {
  standard,
  deluxe,
  expanded,
  anniversary,
  remaster,
  other,
}

class AlbumEdition {
  static const Object _unset = Object();

  const AlbumEdition({
    required this.id,
    required this.albumId,
    required this.title,
    required this.type,
    required this.isPrimary,
    required this.createdAt,
    required this.updatedAt,
    this.releaseDate,
    this.genre,
  });

  final String id;
  final String albumId;
  final String title;
  final AlbumEditionType type;
  final bool isPrimary;
  final DateTime? releaseDate;
  final String? genre;
  final DateTime createdAt;
  final DateTime updatedAt;

  AlbumEdition copyWith({
    String? id,
    String? albumId,
    String? title,
    AlbumEditionType? type,
    bool? isPrimary,
    Object? releaseDate = _unset,
    Object? genre = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlbumEdition(
      id: id ?? this.id,
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      type: type ?? this.type,
      isPrimary: isPrimary ?? this.isPrimary,
      releaseDate: identical(releaseDate, _unset)
          ? this.releaseDate
          : releaseDate as DateTime?,
      genre: identical(genre, _unset) ? this.genre : genre as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is AlbumEdition && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
