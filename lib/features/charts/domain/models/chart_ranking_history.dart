class ChartRankingHistory {
  const ChartRankingHistory({
    required this.entityId,
    required this.finalizedWeeksOnChart,
    required this.hasEverCharted,
    this.previousFinalRank,
    this.previousExtendedRank,
    this.peakRank,
    this.peakAchievedAt,
  });

  final String entityId;

  final int finalizedWeeksOnChart;
  final bool hasEverCharted;

  /// Previous finalized-week rank within the official Top 100.
  final int? previousFinalRank;

  /// Previous finalized-week rank within the persisted Top 200.
  ///
  /// This remains available even when the entity finished outside the
  /// official Top 100, allowing live Moments to distinguish continuation
  /// from a true Top-200 re-entry.
  final int? previousExtendedRank;

  final int? peakRank;
  final DateTime? peakAchievedAt;
}
