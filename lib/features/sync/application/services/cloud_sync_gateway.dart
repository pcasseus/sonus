import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_conditional_write_result.dart';

abstract interface class CloudSyncGateway {
  /// Unconditional write. Only for callers without revision baselines.
  Future<void> upsert(CloudOwnedRecord record);

  /// Inserts [record] only when no row with its id exists.
  ///
  /// An existing row yields a conflict and is never modified.
  Future<CloudConditionalWriteResult> insertIfAbsent(CloudOwnedRecord record);

  /// Replaces a live row only while its server revision still equals
  /// [expectedServerRevision].
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  });

  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  });
}
