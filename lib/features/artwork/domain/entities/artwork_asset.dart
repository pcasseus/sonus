class ArtworkAsset {
  const ArtworkAsset({
    required this.id,
    required this.filePath,
    required this.normalizedPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String filePath;
  final String normalizedPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  ArtworkAsset copyWith({
    String? id,
    String? filePath,
    String? normalizedPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ArtworkAsset(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ArtworkAsset && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
