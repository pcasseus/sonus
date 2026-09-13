import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';

abstract interface class CloudSyncGateway {
  Future<void> upsert(CloudOwnedRecord record);

  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  });
}
