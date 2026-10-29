/// When the newest Moments story was last shown to the user, for the
/// Moments new-content dot (SN-50 F-Q26). No per-story read state.
abstract interface class MomentsLastSeenStore {
  /// Null until Moments have been seen on this device.
  Future<DateTime?> read();

  Future<void> write(DateTime newestSeenUtc);
}
