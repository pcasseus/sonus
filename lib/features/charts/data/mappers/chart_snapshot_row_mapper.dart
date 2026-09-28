import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';

abstract final class ChartSnapshotRowMapper {
  static ChartSnapshot fromRow({
    required Map<String, Object?> snapshotRow,
    required List<ChartEntry> entries,
  }) {
    return ChartSnapshot(
      id: snapshotRow['id']! as String,
      chartType: ChartType.values.firstWhere(
        (value) => value.name == snapshotRow['chart_type'],
      ),
      weekStartUtc: DateTime.parse(snapshotRow['week_start_utc']! as String),
      weekEndUtc: DateTime.parse(snapshotRow['week_end_utc']! as String),
      finalizedAt: snapshotRow['finalized_at'] == null
          ? null
          : DateTime.parse(snapshotRow['finalized_at']! as String),
      revision: snapshotRow['revision']! as int,
      entries: List<ChartEntry>.unmodifiable(entries),
    );
  }

  static Map<String, Object?> toRow({
    required ChartSnapshot snapshot,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return <String, Object?>{
      'id': snapshot.id,
      'chart_type': snapshot.chartType.name,
      'week_start_utc': snapshot.weekStartUtc.toUtc().toIso8601String(),
      'week_end_utc': snapshot.weekEndUtc.toUtc().toIso8601String(),
      'finalized_at': snapshot.finalizedAt?.toUtc().toIso8601String(),
      'revision': snapshot.revision,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
