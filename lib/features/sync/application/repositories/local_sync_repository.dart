import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';

abstract interface class LocalSyncRepository {
  Future<SyncCursor?> getCursor(String userId, CloudDataEntity entityType);

  Future<void> saveCursor(SyncCursor cursor);

  Future<List<SyncOutboxEntry>> getPending(String userId);

  Future<void> recordUpsert({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  });

  Future<void> recordDelete({
    required String? userId,
    required CloudDataEntity entityType,
    required String entityId,
  });

  Future<void> markProcessed({
    required String userId,
    required String outboxEntryId,
    required int expectedRevision,
    required SyncOutboxOperation expectedOperation,
  });
}

/// Ownership capability for pending mutations that were created before
/// a Sonus account was attached.
///
/// This is deliberately separate from [LocalSyncRepository] so normal
/// mutation consumers do not need account-attachment responsibilities.
abstract interface class LocalSyncOwnershipRepository {
  Future<int> claimUnowned(String userId);
}
