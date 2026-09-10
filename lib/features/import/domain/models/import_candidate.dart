class ImportCandidate {
  const ImportCandidate({
    required this.filePath,
    required this.normalizedPath,
    required this.discoveredAt,
  });

  final String filePath;
  final String normalizedPath;
  final DateTime discoveredAt;

  ImportCandidate copyWith({
    String? filePath,
    String? normalizedPath,
    DateTime? discoveredAt,
  }) {
    return ImportCandidate(
      filePath: filePath ?? this.filePath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ImportCandidate && other.normalizedPath == normalizedPath;
  }

  @override
  int get hashCode => normalizedPath.hashCode;
}
