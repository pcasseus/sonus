import '../../domain/models/sync_data_contract.dart';

/// Stores the last safely reconciled cloud revision for each owned entity.
///
/// A missing baseline is represented by null, never by revision 1.
abstract interface class CloudRevisionBaselineRepository {
  Future<int?> getRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  });

  /// Persists a safely observed revision without allowing regression.
  ///
  /// Callers must first establish that the corresponding cloud state
  /// has been reconciled with local data.
  Future<void> saveObservedRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required int serverRevision,
  });
}
