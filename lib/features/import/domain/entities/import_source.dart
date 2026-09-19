class ImportSource {
  const ImportSource({
    required this.id,
    required this.rootPath,
    required this.normalizedRootPath,
    required this.createdAt,
    required this.updatedAt,
    this.lastScannedAt,
  });

  final String id;
  final String rootPath;
  final String normalizedRootPath;
  final DateTime? lastScannedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  ImportSource copyWith({
    String? id,
    String? rootPath,
    String? normalizedRootPath,
    DateTime? lastScannedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ImportSource(
      id: id ?? this.id,
      rootPath: rootPath ?? this.rootPath,
      normalizedRootPath: normalizedRootPath ?? this.normalizedRootPath,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ImportSource && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
