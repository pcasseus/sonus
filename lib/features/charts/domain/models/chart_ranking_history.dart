class ChartRankingHistory {
  const ChartRankingHistory({
    required this.entityId,
    required this.finalizedWeeksOnChart,
    required this.hasEverCharted,
    this.previousFinalRank,
    this.peakRank,
    this.peakAchievedAt,
  });

  final String entityId;

  final int finalizedWeeksOnChart;
  final bool hasEverCharted;

  final int? previousFinalRank;

  final int? peakRank;
  final DateTime? peakAchievedAt;
}
