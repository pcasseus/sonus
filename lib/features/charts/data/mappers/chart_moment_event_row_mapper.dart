import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';

abstract final class ChartMomentEventRowMapper {
  static Map<String, Object?> toRow(ChartMomentEvent event) {
    final related = event.relatedEntity;

    return {
      'id': event.id,
      'deduplication_key': event.deduplicationKey,
      'user_id': event.userId,
      'source_id': event.sourceId,
      'chart_type': event.chartType.name,
      'scope': event.scope.name,
      'event_type': event.eventType.name,
      'entity_id': event.entity.entityId,
      'entity_title': event.entity.title,
      'entity_artist_id': event.entity.artistId,
      'entity_artist_name': event.entity.artistName,
      'entity_album_title': event.entity.albumTitle,
      'related_entity_id': related?.entityId,
      'related_entity_title': related?.title,
      'related_entity_artist_id': related?.artistId,
      'related_entity_artist_name': related?.artistName,
      'related_entity_album_title': related?.albumTitle,
      'week_start_utc': event.weekStartUtc.toUtc().toIso8601String(),
      'week_end_utc': event.weekEndUtc.toUtc().toIso8601String(),
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
      'created_at': event.createdAt.toUtc().toIso8601String(),
      'previous_rank': event.previousRank,
      'current_rank': event.currentRank,
      'threshold': event.threshold,
      'previous_peak_rank': event.previousPeakRank,
      'current_peak_rank': event.currentPeakRank,
      'qualified_stream_count': event.qualifiedStreamCount,
      'milestone_value': event.milestoneValue,
    };
  }

  static ChartMomentEvent fromRow(Map<String, Object?> row) {
    final relatedEntityId = row['related_entity_id'] as String?;

    return ChartMomentEvent(
      id: row['id']! as String,
      deduplicationKey: row['deduplication_key']! as String,
      userId: row['user_id'] as String?,
      sourceId: row['source_id'] as String?,
      chartType: ChartType.values.byName(row['chart_type']! as String),
      scope: ChartMomentScope.values.byName(row['scope']! as String),
      eventType: ChartMomentEventType.values.byName(
        row['event_type']! as String,
      ),
      entity: ChartEntitySnapshot(
        entityId: row['entity_id']! as String,
        title: row['entity_title']! as String,
        artistId: row['entity_artist_id'] as String?,
        artistName: row['entity_artist_name']! as String,
        albumTitle: row['entity_album_title'] as String?,
      ),
      relatedEntity: relatedEntityId == null
          ? null
          : ChartEntitySnapshot(
              entityId: relatedEntityId,
              title: row['related_entity_title']! as String,
              artistId: row['related_entity_artist_id'] as String?,
              artistName: row['related_entity_artist_name']! as String,
              albumTitle: row['related_entity_album_title'] as String?,
            ),
      weekStartUtc: DateTime.parse(row['week_start_utc']! as String).toUtc(),
      weekEndUtc: DateTime.parse(row['week_end_utc']! as String).toUtc(),
      occurredAt: DateTime.parse(row['occurred_at']! as String).toUtc(),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      previousRank: row['previous_rank'] as int?,
      currentRank: row['current_rank'] as int?,
      threshold: row['threshold'] as int?,
      previousPeakRank: row['previous_peak_rank'] as int?,
      currentPeakRank: row['current_peak_rank'] as int?,
      qualifiedStreamCount: row['qualified_stream_count'] as int?,
      milestoneValue: row['milestone_value'] as int?,
    );
  }
}
