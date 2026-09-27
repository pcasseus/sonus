// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../models/analytics_entity_rankings.dart';
import '../models/analytics_period.dart';
import '../models/analytics_ranked_entity.dart';
import 'analytics_time_window_resolver.dart';

class AnalyticsEntityRankingService {
  const AnalyticsEntityRankingService({
    required QualifiedPlayRepository qualifiedPlays,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _qualifiedPlays = qualifiedPlays,
       _timeWindowResolver = timeWindowResolver;

  final QualifiedPlayRepository _qualifiedPlays;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<AnalyticsEntityRankings> load({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Must be greater than zero when provided.',
      );
    }

    final window = _timeWindowResolver.resolve(
      period: period,
      referenceLocal: referenceLocal,
    );

    final plays = await _qualifiedPlays.getAll(
      qualifiedAtOrAfter: window.startUtc,
      qualifiedBefore: window.endUtc,
    );

    return AnalyticsEntityRankings(
      period: period,
      window: window,
      songs: _rank(plays, (play) => play.songId, limit: limit),
      artists: _rank(plays, (play) => play.artistId, limit: limit),
      albums: _rank(plays, (play) => play.albumId, limit: limit),
      albumEditions: _rank(plays, (play) => play.albumEditionId, limit: limit),
    );
  }

  List<AnalyticsRankedEntity> _rank(
    List<QualifiedPlay> plays,
    String Function(QualifiedPlay play) entityIdFor, {
    required int? limit,
  }) {
    final aggregates = <String, _MutableRanking>{};

    for (final play in plays) {
      final entityId = entityIdFor(play);
      final qualifiedAt = play.qualifiedAt.toUtc();

      final existing = aggregates[entityId];

      if (existing == null) {
        aggregates[entityId] = _MutableRanking(
          entityId: entityId,
          qualifiedStreamCount: 1,
          firstQualifiedAt: qualifiedAt,
          lastQualifiedAt: qualifiedAt,
        );

        continue;
      }

      existing.qualifiedStreamCount++;

      if (qualifiedAt.isBefore(existing.firstQualifiedAt)) {
        existing.firstQualifiedAt = qualifiedAt;
      }

      if (qualifiedAt.isAfter(existing.lastQualifiedAt)) {
        existing.lastQualifiedAt = qualifiedAt;
      }
    }

    final rankings = aggregates.values
        .map(
          (entry) => AnalyticsRankedEntity(
            entityId: entry.entityId,
            qualifiedStreamCount: entry.qualifiedStreamCount,
            firstQualifiedAt: entry.firstQualifiedAt,
            lastQualifiedAt: entry.lastQualifiedAt,
          ),
        )
        .toList();

    rankings.sort((a, b) {
      final streamComparison = b.qualifiedStreamCount.compareTo(
        a.qualifiedStreamCount,
      );

      if (streamComparison != 0) {
        return streamComparison;
      }

      final recentComparison = b.lastQualifiedAt.compareTo(a.lastQualifiedAt);

      if (recentComparison != 0) {
        return recentComparison;
      }

      return a.entityId.compareTo(b.entityId);
    });

    if (limit == null || rankings.length <= limit) {
      return List<AnalyticsRankedEntity>.unmodifiable(rankings);
    }

    return List<AnalyticsRankedEntity>.unmodifiable(rankings.take(limit));
  }
}

class _MutableRanking {
  _MutableRanking({
    required this.entityId,
    required this.qualifiedStreamCount,
    required this.firstQualifiedAt,
    required this.lastQualifiedAt,
  });

  final String entityId;

  int qualifiedStreamCount;
  DateTime firstQualifiedAt;
  DateTime lastQualifiedAt;
}
