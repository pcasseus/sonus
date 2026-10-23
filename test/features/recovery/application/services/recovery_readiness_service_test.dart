import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/domain/entities/local_account_binding.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_readiness_report.dart';
import 'package:sonus_next/features/recovery/application/services/account_recovery_eligibility_service.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_consistency_probe.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_inventory_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_readiness_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

final now = DateTime.utc(2026, 10, 21);

class TestBindingRepository implements LocalAccountBindingRepository {
  TestBindingRepository(this.binding, {this.failRead = false});

  final LocalAccountBinding? binding;
  final bool failRead;

  int reads = 0;
  int writes = 0;

  @override
  Future<LocalAccountBinding?> getBinding() async {
    reads++;
    if (failRead) throw StateError('Binding unavailable');
    return binding;
  }

  @override
  Future<void> bindToUser(String userId) async {
    writes++;
    throw StateError('Read-only assessment attempted a write.');
  }

  @override
  Future<void> clearBinding() async {
    writes++;
    throw StateError('Read-only assessment attempted a write.');
  }
}

class TestRecoveryReader implements CloudSyncReader {
  TestRecoveryReader({this.records = const {}, this.failRead = false});

  final Map<CloudDataEntity, List<CloudOwnedRecord>> records;
  final bool failRead;

  int reads = 0;

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    // Recovery inventory only scans pages; it never fetches single rows.
    throw UnsupportedError('fetchCurrent is not used by recovery.');
  }

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    reads++;

    if (failRead) {
      throw StateError('Simulated cloud outage');
    }

    final ordered = List<CloudOwnedRecord>.of(
      records[entityType] ?? const <CloudOwnedRecord>[],
    )..sort((a, b) => a.id.compareTo(b.id));

    final remaining = ordered
        .where((record) => after == null || record.id.compareTo(after.id) > 0)
        .toList();

    final selected = remaining.take(limit).toList();

    return CloudSyncPage(
      items: [
        for (final record in selected)
          CloudSyncItem(record: record, serverUpdatedAt: now),
      ],
      hasMore: remaining.length > selected.length,
    );
  }
}

LocalAccountBinding bindingFor(String userId) {
  return LocalAccountBinding(userId: userId, boundAt: now, updatedAt: now);
}

CloudArtistRecord artist(String id) => CloudArtistRecord(
  id: id,
  userId: 'user-a',
  name: id,
  canonicalName: id,
  createdAt: now,
  updatedAt: now,
);

CloudAlbumRecord album(String id, String artistId) => CloudAlbumRecord(
  id: id,
  userId: 'user-a',
  artistId: artistId,
  title: id,
  canonicalTitle: id,
  createdAt: now,
  updatedAt: now,
);

RecoveryReadinessService buildService(
  TestBindingRepository binding,
  CloudSyncReader reader,
) {
  return RecoveryReadinessService(
    eligibilityService: AccountRecoveryEligibilityService(
      bindingRepository: binding,
    ),
    consistencyProbe: CloudRecoveryConsistencyProbe(
      inventoryService: CloudRecoveryInventoryService(reader: reader),
    ),
  );
}

class ChangingRecoveryReader implements CloudSyncReader {
  int scans = 0;

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) {
    // Recovery inventory only scans pages; it never fetches single rows.
    throw UnsupportedError('fetchCurrent is not used by recovery.');
  }

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

    if (after == null) {
      scans++;
    }

    final ids = ['artist-1', if (scans > 1) 'artist-2'];

    return CloudSyncPage(
      items: [
        for (final id in ids)
          CloudSyncItem(record: artist(id), serverUpdatedAt: now),
      ],
      hasMore: false,
    );
  }
}

void main() {
  test('observed cloud drift blocks recovery readiness', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = ChangingRecoveryReader();

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.observedInstability);
    expect(result.inventory, isNotNull);
    expect(result.inventory!.consistency.hasObservedInstability, isTrue);
    expect(result.canRestore, isFalse);
    expect(reader.scans, 2);
    expect(binding.writes, 0);
  });

  test('observed cloud drift blocks recovery readiness', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = ChangingRecoveryReader();

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.observedInstability);
    expect(result.inventory, isNotNull);
    expect(result.inventory!.consistency.hasObservedInstability, isTrue);
    expect(result.canRestore, isFalse);
    expect(reader.scans, 2);
    expect(binding.writes, 0);
  });

  test('authentication required prevents cloud access', () async {
    final binding = TestBindingRepository(null);
    final reader = TestRecoveryReader();
    final service = buildService(binding, reader);

    final result = await service.assess(authenticatedUserId: null);

    expect(result.status, RecoveryReadinessStatus.authenticationRequired);
    expect(result.canRestore, isFalse);
    expect(reader.reads, 0);
    expect(binding.reads, 0);
    expect(binding.writes, 0);
  });

  test('account conflict prevents cloud access', () async {
    final binding = TestBindingRepository(bindingFor('user-b'));
    final reader = TestRecoveryReader();
    final service = buildService(binding, reader);

    final result = await service.assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.accountConflict);
    expect(reader.reads, 0);
    expect(binding.writes, 0);
  });

  test('empty cloud is not considered recoverable', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = TestRecoveryReader();

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.emptyCloud);
    expect(result.canRestore, isFalse);
    expect(result.hasCloudRecords, isFalse);
    expect(binding.writes, 0);
  });

  test('missing dependencies produce an incomplete report', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = TestRecoveryReader(
      records: {
        CloudDataEntity.album: [album('album-1', 'missing-artist')],
      },
    );

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.incompleteDependencies);
    expect(result.hasDependencyIssues, isTrue);
    expect(result.canRestore, isFalse);
  });

  test('complete cloud relationships still do not authorize restore', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = TestRecoveryReader(
      records: {
        CloudDataEntity.artist: [artist('artist-1')],
        CloudDataEntity.album: [album('album-1', 'artist-1')],
      },
    );

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.incompleteCoverage);
    expect(result.hasUnsupportedCoverage, isTrue);
    expect(result.hasVerifiedCloudSnapshot, isFalse);
    expect(result.canRestore, isFalse);
  });

  test('cloud failures produce interrupted assessments', () async {
    final binding = TestBindingRepository(bindingFor('user-a'));
    final reader = TestRecoveryReader(failRead: true);

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.assessmentInterrupted);
    expect(result.inventory, isNull);
    expect(result.failureReason, isNotNull);
    expect(result.canRestore, isFalse);
  });

  test('binding read failures produce interrupted assessments', () async {
    final binding = TestBindingRepository(null, failRead: true);
    final reader = TestRecoveryReader();

    final result = await buildService(
      binding,
      reader,
    ).assess(authenticatedUserId: 'user-a');

    expect(result.status, RecoveryReadinessStatus.assessmentInterrupted);
    expect(reader.reads, 0);
    expect(result.canRestore, isFalse);
  });

  test(
    'unbound accounts are assessed without claiming local ownership',
    () async {
      final binding = TestBindingRepository(null);
      final reader = TestRecoveryReader();

      final result = await buildService(
        binding,
        reader,
      ).assess(authenticatedUserId: 'user-a');

      expect(result.accountEligible, isTrue);
      expect(result.accountEligibility!.requiresLocalBinding, isTrue);
      expect(result.canRestore, isFalse);
      expect(binding.writes, 0);
    },
  );
}
