class Album {
  const Album({
    required this.id,
    required this.artistId,
    required this.title,
    required this.canonicalTitle,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String artistId;
  final String title;
  final String canonicalTitle;
  final DateTime createdAt;
  final DateTime updatedAt;

  Album copyWith({
    String? id,
    String? artistId,
    String? title,
    String? canonicalTitle,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Album(
      id: id ?? this.id,
      artistId: artistId ?? this.artistId,
      title: title ?? this.title,
      canonicalTitle: canonicalTitle ?? this.canonicalTitle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Album && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
