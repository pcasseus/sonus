import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/models/sync_data_contract.dart';

class CloudRevisionBaselineDao {
  const CloudRevisionBaselineDao(this.db);

  final DatabaseExecutor db;

  Future<int?> getRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    _validateIdentity(userId, entityId);

    final rows = await db.query(
      SyncSchema.cloudRevisionBaselinesTable,
      columns: ['server_revision'],
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, entityType.name, entityId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.single['server_revision'] as int;
  }

  Future<void> saveObservedRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) async {
    _validateIdentity(userId, entityId);

    if (serverRevision < 1) {
      throw ArgumentError.value(
        serverRevision,
        'serverRevision',
        'Must be positive.',
      );
    }

    await db.rawInsert(
      '''
      INSERT INTO ${SyncSchema.cloudRevisionBaselinesTable} (
        user_id, entity_type, entity_id, server_revision
      )
      VALUES (?, ?, ?, ?)
      ON CONFLICT(user_id, entity_type, entity_id)
      DO UPDATE SET
        server_revision = MAX(server_revision, excluded.server_revision)
      ''',
      [userId, entityType.name, entityId, serverRevision],
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
