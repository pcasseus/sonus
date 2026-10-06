import '../../models/analytics_ranked_entity.dart';
import '../../models/monthly_insights/monthly_ranked_entity.dart';

class MonthlyRankingComparisonService {
  const MonthlyRankingComparisonService();

  List<MonthlyRankedEntity> compare({
    required List<AnalyticsRankedEntity> current,
    required List<AnalyticsRankedEntity> previous,
    required List<AnalyticsRankedEntity> lifetime,
  }) {
    final previousById = <String, _RankingPosition>{
      for (var index = 0; index < previous.length; index++)
        previous[index].entityId: _RankingPosition(
          rank: index + 1,
          streams: previous[index].qualifiedStreamCount,
        ),
    };

    final lifetimeStreamsById = <String, int>{
      for (final entity in lifetime)
        entity.entityId: entity.qualifiedStreamCount,
    };

    return List<MonthlyRankedEntity>.unmodifiable(
      List<MonthlyRankedEntity>.generate(current.length, (index) {
        final currentEntity = current[index];
        final previousPosition = previousById[currentEntity.entityId];

        return MonthlyRankedEntity(
          entityId: currentEntity.entityId,
          rank: index + 1,
          previousRank: previousPosition?.rank,
          streams: currentEntity.qualifiedStreamCount,
          previousStreams: previousPosition?.streams ?? 0,
          lifetimeStreams:
              lifetimeStreamsById[currentEntity.entityId] ??
              currentEntity.qualifiedStreamCount,
        );
      }),
    );
  }
}

class _RankingPosition {
  const _RankingPosition({required this.rank, required this.streams});

  final int rank;
  final int streams;
}
