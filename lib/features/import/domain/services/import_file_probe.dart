/// What a read-only check found at a file's path or content URI.
enum ImportFileState {
  present,
  missing,

  /// Sonus no longer has permission to read the file's folder.
  permissionLost,

  /// The check itself failed; nothing is known.
  unknown,
}

/// Checks whether a file can still be reached, without reading, writing,
/// moving or deleting anything.
abstract interface class ImportFileProbe {
  Future<ImportFileState> probe(String filePath);
}
