import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';

abstract final class LocalSyncRowMapper {
  static Map<String, Object?> cursorToRow(SyncCursor cursor) {
    return {
      'user_id': cursor.userId,
      'entity_type': cursor.entityType.name,
      'last_server_updated_at': cursor.lastServerUpdatedAt
          ?.toUtc()
          .toIso8601String(),
      'last_server_id': cursor.lastServerId,
      'updated_at': cursor.updatedAt.toUtc().toIso8601String(),
    };
  }

  static SyncCursor cursorFromRow(Map<String, Object?> row) {
    final lastServerUpdatedAt = row['last_server_updated_at'] as String?;

    return SyncCursor(
      userId: row['user_id'] as String,
      entityType: CloudDataEntity.values.firstWhere(
        (value) => value.name == row['entity_type'],
      ),
      lastServerUpdatedAt: lastServerUpdatedAt == null
          ? null
          : DateTime.parse(lastServerUpdatedAt),
      lastServerId: row['last_server_id'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static Map<String, Object?> outboxToRow(SyncOutboxEntry entry) {
    return {
      'id': entry.id,
      'user_id': entry.userId,
      'entity_type': entry.entityType.name,
      'entity_id': entry.entityId,
      'operation': entry.operation.name,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
      'mutation_revision': entry.mutationRevision,
    };
  }

  static SyncOutboxEntry outboxFromRow(Map<String, Object?> row) {
    return SyncOutboxEntry(
      id: row['id'] as String,
      userId: row['user_id'] as String?,
      entityType: CloudDataEntity.values.firstWhere(
        (value) => value.name == row['entity_type'],
      ),
      entityId: row['entity_id'] as String,
      operation: SyncOutboxOperation.values.firstWhere(
        (value) => value.name == row['operation'],
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      mutationRevision: row['mutation_revision'] as int,
    );
  }
}
