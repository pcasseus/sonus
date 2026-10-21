import '../../../sync/domain/models/sync_data_contract.dart';

class CloudRecoveryRecordEvidence {
  const CloudRecoveryRecordEvidence({
    required this.entityType,
    required this.id,
    required this.serverUpdatedAt,
    required this.serverRevision,
    required this.isDeleted,
  });

  final CloudDataEntity entityType;
  final String id;
  final DateTime serverUpdatedAt;
  final int? serverRevision;
  final bool isDeleted;

  String get identityKey => '${entityType.name}\u0000$id';

  bool matches(CloudRecoveryRecordEvidence other) {
    return entityType == other.entityType &&
        id == other.id &&
        serverUpdatedAt.isAtSameMomentAs(other.serverUpdatedAt) &&
        serverRevision == other.serverRevision &&
        isDeleted == other.isDeleted;
  }
}
