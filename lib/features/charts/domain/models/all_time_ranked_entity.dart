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

  /// Compared with [previousRank]: up, down or same. Without a previous
  /// rank: re-entry if the entity had been in the standings before and was
  /// pushed out, otherwise new.
  final ChartMovement movement;
}
