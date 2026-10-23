import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_consistency.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_consistency_probe.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_inventory_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

final time = DateTime.utc(2026, 10, 21);

CloudArtistRecord artist(String id) => CloudArtistRecord(
  id: id,
  userId: 'user-a',
  name: id,
  canonicalName: id,
  createdAt: time,
  updatedAt: time,
);

class ChangingReader implements CloudSyncReader {
  ChangingReader({required this.changeBetweenScans});

  final bool changeBetweenScans;
  int scans = 0;
  int calls = 0;

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    calls++;

    if (entityType == CloudDataEntity.artist && after == null) {
      scans++;
    }

    if (entityType != CloudDataEntity.artist) {
      return const CloudSyncPage(items: [], hasMore: false);
    }

    final records = <CloudArtistRecord>[
      artist('artist-1'),
      if (changeBetweenScans && scans > 1) artist('artist-2'),
    ];

    return CloudSyncPage(
      items: [
        for (final record in records)
          CloudSyncItem(record: record, serverUpdatedAt: time),
      ],
      hasMore: false,
    );
  }
}

void main() {
  test('matching scans remain unverified', () async {
    final reader = ChangingReader(changeBetweenScans: false);
    final probe = CloudRecoveryConsistencyProbe(
      inventoryService: CloudRecoveryInventoryService(reader: reader),
    );

    final result = await probe.inspect(userId: 'user-a');

    expect(result.activeCount(CloudDataEntity.artist), 1);
    expect(
      result.consistency.status,
      CloudRecoveryConsistencyStatus.unverified,
    );
    expect(result.consistency.isVerified, isFalse);
    expect(reader.scans, 2);
  });

  test('changed inventory counts expose observed instability', () async {
    final reader = ChangingReader(changeBetweenScans: true);
    final probe = CloudRecoveryConsistencyProbe(
      inventoryService: CloudRecoveryInventoryService(reader: reader),
    );

    final result = await probe.inspect(userId: 'user-a');

    expect(result.activeCount(CloudDataEntity.artist), 2);
    expect(
      result.consistency.status,
      CloudRecoveryConsistencyStatus.observedInstability,
    );
    expect(result.consistency.hasObservedInstability, isTrue);
  });

  test('invalid account stops before cloud access', () async {
    final reader = ChangingReader(changeBetweenScans: false);
    final probe = CloudRecoveryConsistencyProbe(
      inventoryService: CloudRecoveryInventoryService(reader: reader),
    );

    await expectLater(probe.inspect(userId: '  '), throwsArgumentError);

    expect(reader.calls, 0);
  });
}
