import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_consistency.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_inventory.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  test('ordinary inventories cannot claim verified consistency', () {
    final inventory = CloudRecoveryInventory(
      activeCounts: {CloudDataEntity.artist: 1},
      tombstoneCounts: {},
    );

    expect(
      inventory.consistency.status,
      CloudRecoveryConsistencyStatus.unverified,
    );
    expect(inventory.consistency.isVerified, isFalse);
  });

  test('unverified consistency is distinct from observed instability', () {
    const consistency = CloudRecoveryConsistency(
      status: CloudRecoveryConsistencyStatus.unverified,
    );

    expect(consistency.isVerified, isFalse);
    expect(consistency.hasObservedInstability, isFalse);
  });

  test('observed instability is explicitly represented', () {
    const consistency = CloudRecoveryConsistency(
      status: CloudRecoveryConsistencyStatus.observedInstability,
      reason: 'Cloud records changed during the assessment.',
    );

    expect(consistency.hasObservedInstability, isTrue);
    expect(consistency.isVerified, isFalse);
  });
}
