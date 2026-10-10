/// A managed artwork file created by one import operation.
///
/// The owner may discard it if the associated database assignment
/// fails or is rejected. A successful assignment retains the file.
abstract interface class OwnedArtworkImport {
  String get filePath;

  /// Deletes only the managed file owned by this import operation.
  Future<void> discard();
}

/// Storage capable of returning an individually owned import.
///
/// Implementations must create a fresh destination and must never
/// return a pre-existing shared artwork file as an owned import.
abstract interface class OwnedArtworkManagedStorage {
  Future<OwnedArtworkImport> importOwnedArtwork(String sourceFilePath);
}
