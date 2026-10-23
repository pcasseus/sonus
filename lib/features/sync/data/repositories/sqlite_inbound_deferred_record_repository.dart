import '../../application/repositories/inbound_deferred_record_repository.dart';
import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/sync_data_contract.dart';
import '../daos/inbound_deferred_record_dao.dart';

class SqliteInboundDeferredRecordRepository
    implements InboundDeferredRecordRepository {
  const SqliteInboundDeferredRecordRepository({required this.dao});

  final InboundDeferredRecordDao dao;

  @override
  Future<void> saveDeferred(InboundDeferredRecord record) {
    return dao.saveDeferred(record);
  }

  @override
  Future<List<InboundDeferredRecord>> getDeferred(String userId) {
    return dao.getDeferred(userId);
  }

  @override
  Future<InboundDeferredRecord?> getDeferral({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return dao.getDeferral(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
    );
  }

  @override
  Future<bool> requeueDeferral({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
    required DateTime deferredAt,
  }) {
    return dao.requeueDeferral(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      serverRevision: serverRevision,
      deferredAt: deferredAt,
    );
  }

  @override
  Future<void> clearThroughRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) {
    return dao.clearThroughRevision(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      serverRevision: serverRevision,
    );
  }
}
