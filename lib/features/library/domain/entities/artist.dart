class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.canonicalName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String canonicalName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Artist copyWith({
    String? id,
    String? name,
    String? canonicalName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      canonicalName: canonicalName ?? this.canonicalName,
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
