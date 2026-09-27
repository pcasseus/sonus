class Artist {
  static const Object _unset = Object();

  const Artist({
    required this.id,
    required this.name,
    required this.canonicalName,
    required this.createdAt,
    required this.updatedAt,
    this.headerArtworkId,
    this.topArtistsArtworkId,
  });

  final String id;
  final String name;
  final String canonicalName;
  final String? headerArtworkId;
  final String? topArtistsArtworkId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Artist copyWith({
    String? id,
    String? name,
    String? canonicalName,
    Object? headerArtworkId = _unset,
    Object? topArtistsArtworkId = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      canonicalName: canonicalName ?? this.canonicalName,
      headerArtworkId: identical(headerArtworkId, _unset)
          ? this.headerArtworkId
          : headerArtworkId as String?,
      topArtistsArtworkId: identical(topArtistsArtworkId, _unset)
          ? this.topArtistsArtworkId
          : topArtistsArtworkId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Artist && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
