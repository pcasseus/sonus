import 'chart_movement.dart';

class ChartRankedEntity {
  const ChartRankedEntity({
    required this.entityId,
    required this.rank,
    required this.qualifiedStreamCount,
    required this.lastQualifiedAt,
    required this.peakRank,
    required this.peakAchievedAt,
    required this.weeksOnChart,
    required this.movement,
    required this.hasEnteredOfficialChartThisWeek,
    required this.hasReenteredOfficialChartThisWeek,
    this.previousFinalRank,
  });

  final String entityId;

  final int rank;
  final int qualifiedStreamCount;
  final DateTime lastQualifiedAt;

  final int? previousFinalRank;

  final int peakRank;
  final DateTime peakAchievedAt;

  final int weeksOnChart;

  final ChartMovement movement;

  final bool hasEnteredOfficialChartThisWeek;
  final bool hasReenteredOfficialChartThisWeek;

  bool get isOfficiallyCharting => rank <= 100;

  bool get isOffChartStanding => rank > 100;
}
