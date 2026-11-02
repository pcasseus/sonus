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

/// Optional read-only capability: whether any account on this device has
/// a cloud baseline for an entity (SN-50 A-Q16). Used when nobody is
/// signed in, so a guard can still tell that an entity reached a cloud.
abstract interface class CloudBaselinePresence {
  Future<bool> hasAnyRevision({
    required CloudDataEntity entityType,
    required String entityId,
  });
}
