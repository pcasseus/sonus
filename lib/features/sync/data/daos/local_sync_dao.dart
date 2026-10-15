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
    final ownerId = entry.userId;

    final where = ownerId == null
        ? 'user_id IS NULL AND entity_type = ? AND entity_id = ?'
        : 'user_id = ? AND entity_type = ? AND entity_id = ?';

    final whereArgs = ownerId == null
        ? <Object?>[entry.entityType.name, entry.entityId]
        : <Object?>[ownerId, entry.entityType.name, entry.entityId];

    Future<int> updateExisting() {
      return db.rawUpdate(
        '''
        UPDATE ${DatabaseTables.syncOutbox}
        SET operation = ?,
            updated_at = ?,
            mutation_revision = mutation_revision + 1
        WHERE $where
        ''',
        [
          entry.operation.name,
          entry.updatedAt.toUtc().toIso8601String(),
          ...whereArgs,
        ],
      );
    }

    final updated = await updateExisting();

    if (updated == 1) {
      return;
    }

    if (updated != 0) {
      throw StateError('Unexpected number of updated outbox rows: $updated.');
    }

    try {
      await db.insert(
        DatabaseTables.syncOutbox,
        LocalSyncRowMapper.outboxToRow(entry),
      );
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError()) {
        rethrow;
      }

      // Another writer may have inserted the same entity after our
      // initial UPDATE. Retry against the row that won the race.
      final retried = await updateExisting();

      if (retried != 1) {
        // The conflict was not resolved by updating the same entity.
        // Preserve the original SQLite error for transaction callers.
        rethrow;
      }
    }
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

  Future<List<SyncOutboxEntry>> findUnownedPending() async {
    final rows = await db.query(
      DatabaseTables.syncOutbox,
      where: 'user_id IS NULL',
      orderBy: 'created_at ASC, id ASC',
    );

    return rows.map(LocalSyncRowMapper.outboxFromRow).toList(growable: false);
  }

  Future<int> claimUnowned(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    final unowned = await findUnownedPending();
    var claimedCount = 0;

    for (final anonymousEntry in unowned) {
      final ownedRows = await db.query(
        DatabaseTables.syncOutbox,
        where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [
          normalizedUserId,
          anonymousEntry.entityType.name,
          anonymousEntry.entityId,
        ],
        limit: 1,
      );

      if (ownedRows.isEmpty) {
        final updated = await db.update(
          DatabaseTables.syncOutbox,
          {'user_id': normalizedUserId},
          where: 'id = ? AND user_id IS NULL',
          whereArgs: [anonymousEntry.id],
        );

        claimedCount += updated;
        continue;
      }

      final ownedEntry = LocalSyncRowMapper.outboxFromRow(ownedRows.single);

      final anonymousIsLater =
          anonymousEntry.updatedAt.isAfter(ownedEntry.updatedAt) ||
          (anonymousEntry.updatedAt == ownedEntry.updatedAt &&
              anonymousEntry.id.compareTo(ownedEntry.id) > 0);

      final winningOperation = anonymousIsLater
          ? anonymousEntry.operation
          : ownedEntry.operation;

      final earliestCreatedAt =
          anonymousEntry.createdAt.isBefore(ownedEntry.createdAt)
          ? anonymousEntry.createdAt
          : ownedEntry.createdAt;

      final latestUpdatedAt =
          anonymousEntry.updatedAt.isAfter(ownedEntry.updatedAt)
          ? anonymousEntry.updatedAt
          : ownedEntry.updatedAt;

      await db.rawUpdate(
        '''
        UPDATE ${DatabaseTables.syncOutbox}
        SET operation = ?,
            created_at = ?,
            updated_at = ?,
            mutation_revision = mutation_revision + 1
        WHERE id = ?
        ''',
        [
          winningOperation.name,
          earliestCreatedAt.toUtc().toIso8601String(),
          latestUpdatedAt.toUtc().toIso8601String(),
          ownedEntry.id,
        ],
      );

      await db.delete(
        DatabaseTables.syncOutbox,
        where: 'id = ? AND user_id IS NULL',
        whereArgs: [anonymousEntry.id],
      );

      claimedCount++;
    }

    return claimedCount;
  }

  Future<void> removeOutboxEntry({
    required String userId,
    required String id,
    required int expectedRevision,
    required SyncOutboxOperation expectedOperation,
  }) async {
    await db.delete(
      DatabaseTables.syncOutbox,
      where:
          'user_id = ? AND id = ? AND mutation_revision = ? '
          'AND operation = ?',
      whereArgs: [userId, id, expectedRevision, expectedOperation.name],
    );
  }
}
