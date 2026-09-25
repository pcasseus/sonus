enum ImportCandidateStructure { singleFile, artistAlbum, looseAlbum }

class ImportCandidate {
  const ImportCandidate({
    required this.filePath,
    required this.normalizedPath,
    required this.discoveredAt,
    this.metadataFallbackPath,
    this.lyricsPath,
    this.sourceId,
    this.structure = ImportCandidateStructure.singleFile,
  });

  final String filePath;
  final String normalizedPath;
  final DateTime discoveredAt;
  final String? metadataFallbackPath;
  final String? lyricsPath;
  final String? sourceId;
  final ImportCandidateStructure structure;

  ImportCandidate copyWith({
    String? filePath,
    String? normalizedPath,
    DateTime? discoveredAt,
    String? metadataFallbackPath,
    String? lyricsPath,
    String? sourceId,
    ImportCandidateStructure? structure,
  }) {
    return ImportCandidate(
      filePath: filePath ?? this.filePath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      metadataFallbackPath: metadataFallbackPath ?? this.metadataFallbackPath,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      sourceId: sourceId ?? this.sourceId,
      structure: structure ?? this.structure,
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
