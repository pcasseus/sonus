import 'chart_movement.dart';

/// One standing on the permanent all-time chart.
class AllTimeRankedEntity {
  const AllTimeRankedEntity({
    required this.entityId,
    required this.rank,
    required this.lifetimeStreamCount,
    required this.lastQualifiedAt,
    required this.peakRank,
    required this.peakAchievedAt,
    required this.movement,
    this.previousRank,
    this.priorPeakRank,
    this.firstChartedAt,
    this.firstHot100At,
  });

  final String entityId;

  final int rank;

  /// Every qualified play ever counted for this entity.
  final int lifetimeStreamCount;

  /// When the latest qualified play was counted. That play is also when the
  /// current total was reached.
  final DateTime lastQualifiedAt;

  /// Best all-time rank its play history reached, replayed from every play,
  /// or the current rank if that is better.
  final int peakRank;
  final DateTime peakAchievedAt;

  /// All-time rank at the comparison start, if it was within the standings.
  final int? previousRank;

  /// Display-only (Charts 2.0 C2): the peak as of the comparison point, and
  /// when the entry first reached the Top 200 / Top 100 after it.
  final int? priorPeakRank;
  final DateTime? firstChartedAt;
  final DateTime? firstHot100At;

  /// Compared with [previousRank]: up, down or same. Without a previous
  /// rank: re-entry if the entity had been in the standings before and was
  /// pushed out, otherwise new.
  final ChartMovement movement;
}
