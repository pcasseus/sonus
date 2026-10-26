/// Which releases chart as releases (SN-45). A Single charts through its
/// songs on the Sonus Hot 100 only: it never takes a place, a debut or a
/// Moment on the release chart. Albums and EPs chart as releases.
abstract interface class ReleaseChartEligibility {
  /// Releases that never chart as releases (Singles), by album id.
  Future<Set<String>> excludedAlbumIds();
}

/// Loads [eligibility]'s exclusions, or none when there is no eligibility.
Future<Set<String>> excludedReleaseIds(ReleaseChartEligibility? eligibility) =>
    eligibility?.excludedAlbumIds() ?? Future.value(const <String>{});
