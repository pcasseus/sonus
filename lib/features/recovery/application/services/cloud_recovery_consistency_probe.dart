import '../../../sync/domain/models/sync_data_contract.dart';
import '../models/cloud_recovery_consistency.dart';
import '../models/cloud_recovery_dependency_issue.dart';
import '../models/cloud_recovery_inventory.dart';
import 'cloud_recovery_inventory_service.dart';

class CloudRecoveryConsistencyProbe {
  const CloudRecoveryConsistencyProbe({required this.inventoryService});

  final CloudRecoveryInventoryService inventoryService;

  Future<CloudRecoveryInventory> inspect({
    required String userId,
    int pageSize = 100,
  }) async {
    final first = await inventoryService.inspect(
      userId: userId,
      pageSize: pageSize,
    );

    final second = await inventoryService.inspect(
      userId: userId,
      pageSize: pageSize,
    );

    final changed = !_sameSummary(first, second);

    return CloudRecoveryInventory(
      activeCounts: second.activeCounts,
      tombstoneCounts: second.tombstoneCounts,
      dependencyIssues: second.dependencyIssues,
      recordEvidence: second.recordEvidence,
      consistency: CloudRecoveryConsistency(
        status: changed
            ? CloudRecoveryConsistencyStatus.observedInstability
            : CloudRecoveryConsistencyStatus.unverified,
        reason: changed
            ? 'Cloud inventory summaries differed between scans.'
            : 'Two scans agreed, but no transactional snapshot was available.',
      ),
    );
  }

  bool _sameSummary(
    CloudRecoveryInventory first,
    CloudRecoveryInventory second,
  ) {
    for (final entity in CloudDataEntity.values) {
      if (first.activeCount(entity) != second.activeCount(entity) ||
          first.tombstoneCount(entity) != second.tombstoneCount(entity)) {
        return false;
      }
    }

    if (first.recordEvidence.length != second.recordEvidence.length) {
      return false;
    }

    for (final entry in first.recordEvidence.entries) {
      final other = second.recordEvidence[entry.key];

      if (other == null || !entry.value.matches(other)) {
        return false;
      }
    }

    final firstIssues = first.dependencyIssues.map(_issueKey).toList()..sort();
    final secondIssues = second.dependencyIssues.map(_issueKey).toList()
      ..sort();

    if (firstIssues.length != secondIssues.length) {
      return false;
    }

    for (var index = 0; index < firstIssues.length; index++) {
      if (firstIssues[index] != secondIssues[index]) {
        return false;
      }
    }

    return true;
  }

  String _issueKey(CloudRecoveryDependencyIssue issue) {
    return [
      issue.kind.name,
      issue.entityId,
      issue.fieldName,
      issue.referencedId ?? '',
    ].join('\u0000');
  }
}
