import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/sync_data_contract.dart';

/// Durable ledger of cloud revisions passed by the inbound cursor
/// without being applied locally.
abstract interface class InboundDeferredRecordRepository {
  /// Records or advances a deferral. A lower revision never replaces a
  /// higher one.
  Future<void> saveDeferred(InboundDeferredRecord record);

  Future<List<InboundDeferredRecord>> getDeferred(String userId);

  Future<InboundDeferredRecord?> getDeferral({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  });

  /// Moves an obligation still at [serverRevision] to the back of the
  /// replay queue without changing its revision or reason. Never inserts.
  /// Returns whether the obligation was requeued.
  Future<bool> requeueDeferral({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
    required DateTime deferredAt,
  });

  /// Removes a deferral once a revision at or above it has been applied.
  Future<void> clearThroughRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  });
}
