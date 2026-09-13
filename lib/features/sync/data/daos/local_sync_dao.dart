import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import '../mappers/local_sync_row_mapper.dart';

class LocalSyncDao {
  const LocalSyncDao(this.db);

  final DatabaseExecutor db;

  Future<void> saveCursor(SyncCursor cursor) async {
    await db.insert(
      DatabaseTables.syncState,
      LocalSyncRowMapper.cursorToRow(cursor),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SyncCursor?> findCursor(
    String userId,
    CloudDataEntity entityType,
  ) async {
    final rows = await db.query(
      DatabaseTables.syncState,
      where: 'user_id = ? AND entity_type = ?',
      whereArgs: [userId, entityType.name],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return LocalSyncRowMapper.cursorFromRow(rows.single);
  }

  Future<void> enqueue(SyncOutboxEntry entry) async {
    await db.rawInsert(
      '''
      INSERT INTO ${DatabaseTables.syncOutbox} (
        id,
        user_id,
        entity_type,
        entity_id,
        operation,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
        operation = excluded.operation,
        updated_at = excluded.updated_at
      ''',
      [
        entry.id,
        entry.userId,
        entry.entityType.name,
        entry.entityId,
        entry.operation.name,
        entry.createdAt.toUtc().toIso8601String(),
        entry.updatedAt.toUtc().toIso8601String(),
      ],
    );
  }

  Future<List<SyncOutboxEntry>> findPending(String userId) async {
    final rows = await db.query(
      DatabaseTables.syncOutbox,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC, id ASC',
    );

    return rows.map(LocalSyncRowMapper.outboxFromRow).toList(growable: false);
  }

  Future<void> removeOutboxEntry({
    required String userId,
    required String id,
  }) async {
    await db.delete(
      DatabaseTables.syncOutbox,
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
  }
}
