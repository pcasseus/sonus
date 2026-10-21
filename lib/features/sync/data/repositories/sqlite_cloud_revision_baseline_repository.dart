import '../../application/repositories/cloud_revision_baseline_repository.dart';
import '../../domain/models/sync_data_contract.dart';
import '../daos/cloud_revision_baseline_dao.dart';

class SqliteCloudRevisionBaselineRepository
    implements CloudRevisionBaselineRepository {
  const SqliteCloudRevisionBaselineRepository({required this.dao});

  final CloudRevisionBaselineDao dao;

  @override
  Future<int?> getRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    return dao.getRevision(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
    );
  }

  @override
  Future<void> saveObservedRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  }) {
    return dao.saveObservedRevision(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      serverRevision: serverRevision,
    );
  }
}
