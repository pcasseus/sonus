/// When verified duplicate releases are merged automatically (App Update
/// 1.2, see DuplicateAlbumReconciliationService).
abstract final class DuplicateReconciliationPolicy {
  /// After every full scan of an import source.
  ///
  /// **Off** in this build. Turning it on merges the user's existing
  /// duplicates (the three "Zendaya" albums) on the next scan, which the
  /// user has asked to authorise separately. It also needs the cloud
  /// deletion guards, so another device cannot bring the merged duplicates
  /// back. Tests construct the hook directly.
  static const bool automaticAfterScan = false;
}
