import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_consistency.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_consistency_probe.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_inventory_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

enum EvidenceChange { identity, timestamp, revision }

class EvidenceChangingReader implements CloudSyncReader {
  EvidenceChangingReader(this.change);

  final EvidenceChange change;
  int scans = 0;

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    if (entityType != CloudDataEntity.artist) {
      return const CloudSyncPage(items: [], hasMore: false);
    }

    scans++;

    final second = scans > 1;
    final time = DateTime.utc(2026, 10, 21);
    final changedTime = time.add(const Duration(minutes: 1));

    final id = second && change == EvidenceChange.identity
        ? 'artist-2'
        : 'artist-1';

    final serverTime = second && change == EvidenceChange.timestamp
        ? changedTime
        : time;

    final revision = second && change == EvidenceChange.revision ? 2 : 1;

    final record = CloudArtistRecord(
      id: id,
      userId: userId,
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: time,
      updatedAt: serverTime,
    );

    return CloudSyncPage(
      items: [
        CloudSyncItem(
          record: record,
          serverUpdatedAt: serverTime,
          serverRevision: revision,
        ),
      ],
      hasMore: false,
    );
  }
}

void main() {
  for (final change in EvidenceChange.values) {
    test('detects ${change.name} changes with identical counts', () async {
      final reader = EvidenceChangingReader(change);

      final probe = CloudRecoveryConsistencyProbe(
        inventoryService: CloudRecoveryInventoryService(reader: reader),
      );

      final result = await probe.inspect(userId: 'user-a');

      expect(result.activeCount(CloudDataEntity.artist), 1);
      expect(result.hasDependencyIssues, isFalse);
      expect(result.recordEvidence.length, 1);
      expect(reader.scans, 2);

      expect(
        result.consistency.status,
        CloudRecoveryConsistencyStatus.observedInstability,
      );
    });
  }
}
