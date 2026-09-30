import '../../application/repositories/local_sync_repository.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import '../daos/local_sync_dao.dart';

typedef SyncIdGenerator = String Function();
typedef SyncClock = DateTime Function();

class SqliteLocalSyncRepository
    implements LocalSyncRepository, LocalSyncOwnershipRepository {
  const SqliteLocalSyncRepository({
    required this.dao,
    required this.generateId,
    required this.now,
  });

  final LocalSyncDao dao;
  final SyncIdGenerator generateId;
  final SyncClock now;

  @override
  Future<SyncCursor?> getCursor(String userId, CloudDataEntity entityType) {
    return dao.findCursor(userId, entityType);
  }

  @override
  Future<void> saveCursor(SyncCursor cursor) {
    return dao.saveCursor(cursor);
  }

  @override
  Future<List<SyncOutboxEntry>> getPending(String userId) {
    return dao.findPending(userId);
  }

  @override
  Future<void> recordUpsert({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return _recordMutation(
      userId: _normalizeUserId(userId),
      entityType: entityType,
      entityId: entityId,
      operation: SyncOutboxOperation.upsert,
    );
  }

  @override
  Future<void> recordDelete({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return _recordMutation(
      userId: _normalizeUserId(userId),
      entityType: entityType,
      entityId: entityId,
      operation: SyncOutboxOperation.delete,
    );
  }

  @override
  Future<int> claimUnowned(String userId) {
    return dao.claimUnowned(userId);
  }

  @override
  Future<void> markProcessed({
    required String userId,
    required String outboxEntryId,
  }) {
    return dao.removeOutboxEntry(userId: userId, id: outboxEntryId);
  }

  Future<void> _recordMutation({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
    required SyncOutboxOperation operation,
  }) {
    final timestamp = now().toUtc();

    return dao.enqueue(
      SyncOutboxEntry(
        id: generateId(),
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  String? _normalizeUserId(String? userId) {
    final normalized = userId?.trim();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
