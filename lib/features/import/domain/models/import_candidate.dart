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
    this.fileSizeBytes,
    this.modifiedAt,
  });

  final String filePath;
  final String normalizedPath;
  final DateTime discoveredAt;
  final String? metadataFallbackPath;
  final String? lyricsPath;
  final String? sourceId;
  final ImportCandidateStructure structure;

  /// The file's size and last change, when the discovery listed them
  /// (BUG-09): a changed file is read again, an unchanged one is not.
  final int? fileSizeBytes;
  final DateTime? modifiedAt;

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
      fileSizeBytes: fileSizeBytes,
      modifiedAt: modifiedAt,
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
