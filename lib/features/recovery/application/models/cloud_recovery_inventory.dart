import '../../../sync/domain/models/sync_data_contract.dart';
import 'cloud_recovery_dependency_issue.dart';

class CloudRecoveryInventory {
  CloudRecoveryInventory({
    required Map<CloudDataEntity, int> activeCounts,
    required Map<CloudDataEntity, int> tombstoneCounts,
    List<CloudRecoveryDependencyIssue> dependencyIssues = const [],
  }) : activeCounts = Map.unmodifiable(activeCounts),
       tombstoneCounts = Map.unmodifiable(tombstoneCounts),
       dependencyIssues = List.unmodifiable(dependencyIssues);

  final Map<CloudDataEntity, int> activeCounts;
  final Map<CloudDataEntity, int> tombstoneCounts;
  final List<CloudRecoveryDependencyIssue> dependencyIssues;

  bool get hasDependencyIssues => dependencyIssues.isNotEmpty;

  int activeCount(CloudDataEntity entity) => activeCounts[entity] ?? 0;

  int tombstoneCount(CloudDataEntity entity) => tombstoneCounts[entity] ?? 0;

  int get totalActive =>
      activeCounts.values.fold(0, (sum, count) => sum + count);

  int get totalTombstones =>
      tombstoneCounts.values.fold(0, (sum, count) => sum + count);

  bool get hasCloudRecords => totalActive + totalTombstones > 0;

  // Inventory enumeration alone does not prove restoration readiness.
}
