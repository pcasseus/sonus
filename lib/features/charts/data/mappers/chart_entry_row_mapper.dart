import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_movement.dart';

abstract final class ChartEntryRowMapper {
  static ChartEntry fromRow(Map<String, Object?> row) {
    return ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: row['entity_id']! as String,
        title: row['title']! as String,
        artistId: row['artist_id'] as String?,
        artistName: row['artist_name']! as String,
        albumTitle: row['album_title'] as String?,
      ),
      rank: row['rank']! as int,
      qualifiedStreamCount: row['qualified_stream_count']! as int,
      lastQualifiedAt: DateTime.parse(row['last_qualified_at']! as String),
      previousFinalRank: row['previous_final_rank'] as int?,
      peakRank: row['peak_rank']! as int,
      peakAchievedAt: DateTime.parse(row['peak_achieved_at']! as String),
      weeksOnChart: row['weeks_on_chart']! as int,
      movement: ChartMovement.values.firstWhere(
        (value) => value.name == row['movement'],
      ),
    );
  }

  static Map<String, Object?> toRow({
    required String snapshotId,
    required ChartEntry entry,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return <String, Object?>{
      'id': '$snapshotId:${entry.entity.entityId}',
      'chart_snapshot_id': snapshotId,
      'entity_id': entry.entity.entityId,
      'title': entry.entity.title,
      'artist_id': entry.entity.artistId,
      'artist_name': entry.entity.artistName,
      'album_title': entry.entity.albumTitle,
      'rank': entry.rank,
      'qualified_stream_count': entry.qualifiedStreamCount,
      'previous_final_rank': entry.previousFinalRank,
      'peak_rank': entry.peakRank,
      'peak_achieved_at': entry.peakAchievedAt.toUtc().toIso8601String(),
      'weeks_on_chart': entry.weeksOnChart,
      'movement': entry.movement.name,
      'last_qualified_at': entry.lastQualifiedAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
