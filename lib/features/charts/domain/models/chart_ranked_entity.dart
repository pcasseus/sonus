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
    this.previousExtendedRank,
    this.priorPeakRank,
    this.firstChartedAt,
    this.firstHot100At,
  });

  final String entityId;

  final int rank;
  final int qualifiedStreamCount;
  final DateTime lastQualifiedAt;

  final int? previousFinalRank;

  /// Display-only facts for chart movement (Charts 2.0 C2), derived from
  /// the same replay; never stored and never used for ranking.
  ///
  /// The previous finalized week's rank within the Top 200, so Bubbling
  /// Under can show its own movement.
  final int? previousExtendedRank;

  /// The best finalized position before this period (null: none), so a
  /// new peak is judged against finalized history only.
  final int? priorPeakRank;

  /// When the entry first reached the Top 200 / the Top 100 in this
  /// period's replay (null: unknown or never).
  final DateTime? firstChartedAt;
  final DateTime? firstHot100At;

  final int peakRank;
  final DateTime peakAchievedAt;

  final int weeksOnChart;

  final ChartMovement movement;

  final bool hasEnteredOfficialChartThisWeek;
  final bool hasReenteredOfficialChartThisWeek;

  bool get isOfficiallyCharting => rank <= 100;

  bool get isOffChartStanding => rank > 100;
}
