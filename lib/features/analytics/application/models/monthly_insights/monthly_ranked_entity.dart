import 'monthly_ranking_change.dart';

class MonthlyRankedEntity {
  const MonthlyRankedEntity({
    required this.entityId,
    required this.rank,
    required this.previousRank,
    required this.streams,
    required this.previousStreams,
    required this.lifetimeStreams,
  });

  final String entityId;

  final int rank;
  final int? previousRank;

  final int streams;
  final int previousStreams;
  final int lifetimeStreams;

  MonthlyRankingChange get streamChange => MonthlyRankingChange(
    currentValue: streams,
    previousValue: previousStreams,
  );

  bool get isNew => previousRank == null && previousStreams == 0;

  int? get rankMovement {
    final previous = previousRank;

    if (previous == null) {
      return null;
    }

    return previous - rank;
  }

  bool get movedUp => (rankMovement ?? 0) > 0;

  bool get movedDown => (rankMovement ?? 0) < 0;

  bool get stayedAtSameRank => rankMovement == 0;
}
