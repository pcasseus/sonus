import '../../domain/models/outbound_sync_conflict.dart';
import '../../domain/models/sync_data_contract.dart';

/// Durable ledger of outbound mutations rejected by cloud state.
abstract interface class OutboundConflictRepository {
  /// Records or replaces the conflict for one entity.
  Future<void> record(OutboundSyncConflict conflict);

  Future<OutboundSyncConflict?> get({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  });

  Future<List<OutboundSyncConflict>> getAll(String userId);

  Future<void> clear({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  });
}
