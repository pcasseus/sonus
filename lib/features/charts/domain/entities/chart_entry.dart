import '../models/chart_entity_snapshot.dart';
import '../models/chart_movement.dart';

class ChartEntry {
  const ChartEntry({
    required this.entity,
    required this.rank,
    required this.qualifiedStreamCount,
    required this.lastQualifiedAt,
    required this.peakRank,
    required this.peakAchievedAt,
    required this.weeksOnChart,
    required this.movement,
    this.previousFinalRank,
  });

  final ChartEntitySnapshot entity;

  final int rank;
  final int qualifiedStreamCount;
  final DateTime lastQualifiedAt;

  final int? previousFinalRank;

  final int peakRank;
  final DateTime peakAchievedAt;

  final int weeksOnChart;

  final ChartMovement movement;

  bool get isOfficiallyCharting => rank <= 100;

  bool get isOffChartStanding => rank > 100;
}
