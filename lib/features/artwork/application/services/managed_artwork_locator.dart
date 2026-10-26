/// Storage that can tell whether a file is already one of its own managed
/// artwork files.
///
/// Assigning such a file again (for example restoring an uncropped
/// original, SN-45) reuses it instead of storing another copy. Managed files
/// are never modified in place, so sharing one is safe.
abstract interface class ManagedArtworkLocator {
  Future<bool> isManagedArtwork(String filePath);
}
