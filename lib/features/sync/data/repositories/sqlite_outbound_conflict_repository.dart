import '../../application/repositories/outbound_conflict_repository.dart';
import '../../domain/models/outbound_sync_conflict.dart';
import '../../domain/models/sync_data_contract.dart';
import '../daos/outbound_conflict_dao.dart';

class SqliteOutboundConflictRepository implements OutboundConflictRepository {
  const SqliteOutboundConflictRepository({required this.dao});

  final OutboundConflictDao dao;

  @override
  Future<void> record(OutboundSyncConflict conflict) => dao.record(conflict);

  @override
  Future<OutboundSyncConflict?> get({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return dao.get(userId: userId, entityType: entityType, entityId: entityId);
  }

  @override
  Future<List<OutboundSyncConflict>> getAll(String userId) {
    return dao.getAll(userId);
  }

  @override
  Future<void> clear({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return dao.clear(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
    );
  }
}
