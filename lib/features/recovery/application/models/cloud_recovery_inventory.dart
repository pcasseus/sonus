import '../../../sync/domain/models/sync_data_contract.dart';

class CloudRecoveryInventory {
  CloudRecoveryInventory({
    required Map<CloudDataEntity, int> activeCounts,
    required Map<CloudDataEntity, int> tombstoneCounts,
  }) : activeCounts = Map.unmodifiable(activeCounts),
       tombstoneCounts = Map.unmodifiable(tombstoneCounts);

  final Map<CloudDataEntity, int> activeCounts;
  final Map<CloudDataEntity, int> tombstoneCounts;

  int activeCount(CloudDataEntity entity) => activeCounts[entity] ?? 0;

  int tombstoneCount(CloudDataEntity entity) => tombstoneCounts[entity] ?? 0;

  int get totalActive =>
      activeCounts.values.fold(0, (sum, count) => sum + count);

  int get totalTombstones =>
      tombstoneCounts.values.fold(0, (sum, count) => sum + count);

  bool get hasCloudRecords => totalActive + totalTombstones > 0;

  // Inventory enumeration alone does not prove restoration readiness.
}
