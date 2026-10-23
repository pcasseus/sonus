import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/sync_data_contract.dart';

class InboundDeferredRecordDao {
  const InboundDeferredRecordDao(this.db);

  final DatabaseExecutor db;

  Future<void> saveDeferred(InboundDeferredRecord record) async {
    _validateIdentity(record.userId, record.entityId);

    if (record.serverRevision < 1) {
      throw ArgumentError.value(
        record.serverRevision,
        'serverRevision',
        'Must be positive.',
      );
    }

    await db.rawInsert(
      '''
      INSERT INTO ${SyncSchema.inboundDeferredRecordsTable} (
        user_id, entity_type, entity_id, server_revision,
        server_updated_at, reason, deferred_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, entity_type, entity_id)
      DO UPDATE SET
        server_revision = excluded.server_revision,
        server_updated_at = excluded.server_updated_at,
        reason = excluded.reason,
        deferred_at = excluded.deferred_at
      WHERE excluded.server_revision >= server_revision
      ''',
      [
        record.userId,
        record.entityType.name,
        record.entityId,
        record.serverRevision,
        record.serverUpdatedAt.toUtc().toIso8601String(),
        record.reason.name,
        record.deferredAt.toUtc().toIso8601String(),
      ],
    );
  }

  Future<List<InboundDeferredRecord>> getDeferred(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    final rows = await db.query(
      SyncSchema.inboundDeferredRecordsTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'server_updated_at, entity_type, entity_id',
    );

    return rows.map(_fromRow).toList(growable: false);
  }

  Future<InboundDeferredRecord?> getDeferral({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    _validateIdentity(userId, entityId);

    final rows = await db.query(
      SyncSchema.inboundDeferredRecordsTable,
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, entityType.name, entityId],
      limit: 1,
    );

    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  InboundDeferredRecord _fromRow(Map<String, Object?> row) {
    return InboundDeferredRecord(
      userId: row['user_id'] as String,
      entityType: CloudDataEntity.values.byName(row['entity_type'] as String),
      entityId: row['entity_id'] as String,
      serverRevision: row['server_revision'] as int,
      serverUpdatedAt: DateTime.parse(
        row['server_updated_at'] as String,
      ).toUtc(),
      reason: InboundDeferralReason.values.byName(row['reason'] as String),
      deferredAt: DateTime.parse(row['deferred_at'] as String).toUtc(),
    );
  }

  Future<void> clearThroughRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) async {
    _validateIdentity(userId, entityId);

    await db.delete(
      SyncSchema.inboundDeferredRecordsTable,
      where:
          'user_id = ? AND entity_type = ? AND entity_id = ? '
          'AND server_revision <= ?',
      whereArgs: [userId, entityType.name, entityId, serverRevision],
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
