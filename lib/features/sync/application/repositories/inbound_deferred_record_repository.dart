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

  /// Removes a deferral once a revision at or above it has been applied.
  Future<void> clearThroughRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  });
}
