import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/outbound_sync_conflict.dart';
import '../../domain/models/sync_data_contract.dart';

class OutboundConflictDao {
  const OutboundConflictDao(this.db);

  final DatabaseExecutor db;

  static const _table = SyncSchema.outboundConflictsTable;

  Future<void> record(OutboundSyncConflict conflict) async {
    _validateIdentity(conflict.userId, conflict.entityId);

    await db.insert(_table, {
      'user_id': conflict.userId,
      'entity_type': conflict.entityType.name,
      'entity_id': conflict.entityId,
      'outbox_id': conflict.outboxId,
      'mutation_revision': conflict.mutationRevision,
      'operation': conflict.operation.name,
      'expected_server_revision': conflict.expectedServerRevision,
      'observed_server_revision': conflict.observedServerRevision,
      'observed_state': conflict.observedState.name,
      'detected_at': conflict.detectedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OutboundSyncConflict?> get({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    _validateIdentity(userId, entityId);

    final rows = await db.query(
      _table,
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, entityType.name, entityId],
      limit: 1,
    );

    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<List<OutboundSyncConflict>> getAll(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    final rows = await db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'detected_at, entity_type, entity_id',
    );

    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> clear({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    _validateIdentity(userId, entityId);

    await db.delete(
      _table,
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, entityType.name, entityId],
    );
  }

  /// Removes the entity's conflict once [mutationRevision] of [outboxId]
  /// was accepted by the cloud. A conflict recorded for a newer revision of
  /// the same outbox entry is kept. One outbox entry exists per entity, so
  /// a conflict naming another entry refers to one already superseded.
  Future<void> clearResolved({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required String outboxId,
    required int mutationRevision,
  }) async {
    _validateIdentity(userId, entityId);

    await db.delete(
      _table,
      where:
          'user_id = ? AND entity_type = ? AND entity_id = ? '
          'AND NOT (outbox_id = ? AND mutation_revision > ?)',
      whereArgs: [
        userId,
        entityType.name,
        entityId,
        outboxId,
        mutationRevision,
      ],
    );
  }

  OutboundSyncConflict _fromRow(Map<String, Object?> row) {
    return OutboundSyncConflict(
      userId: row['user_id'] as String,
      entityType: CloudDataEntity.values.byName(row['entity_type'] as String),
      entityId: row['entity_id'] as String,
      outboxId: row['outbox_id'] as String,
      mutationRevision: row['mutation_revision'] as int,
      operation: SyncOutboxOperation.values.byName(row['operation'] as String),
      expectedServerRevision: row['expected_server_revision'] as int?,
      observedServerRevision: row['observed_server_revision'] as int?,
      observedState: OutboundConflictCloudState.values.byName(
        row['observed_state'] as String,
      ),
      detectedAt: DateTime.parse(row['detected_at'] as String).toUtc(),
    );
  }

  void _validateIdentity(String userId, String entityId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    if (entityId.trim().isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'Must not be blank.');
    }
  }
}
