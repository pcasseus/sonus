import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_dependency_issue.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_inventory_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

final timestamp = DateTime.utc(2026, 10, 21);

class DependencyTestReader implements CloudSyncReader {
  DependencyTestReader(this.records);

  final Map<CloudDataEntity, List<CloudOwnedRecord>> records;
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

    final sorted = List<CloudOwnedRecord>.of(
      records[entityType] ?? const <CloudOwnedRecord>[],
    )..sort((a, b) => a.id.compareTo(b.id));

    final remaining = sorted
        .where((record) => after == null || record.id.compareTo(after.id) > 0)
        .toList();

    final selected = remaining.take(limit).toList();

    return CloudSyncPage(
      items: [
        for (final record in selected)
          CloudSyncItem(record: record, serverUpdatedAt: timestamp),
      ],
      hasMore: remaining.length > selected.length,
    );
  }
}

CloudArtistRecord artist(String id) => CloudArtistRecord(
  id: id,
  userId: 'user-a',
  name: id,
  canonicalName: id,
  createdAt: timestamp,
  updatedAt: timestamp,
);

CloudAlbumRecord album(String id, String artistId) => CloudAlbumRecord(
  id: id,
  userId: 'user-a',
  artistId: artistId,
  title: id,
  canonicalTitle: id,
  createdAt: timestamp,
  updatedAt: timestamp,
);

void main() {
  test('integrated inventory reports missing dependencies', () async {
    final reader = DependencyTestReader({
      CloudDataEntity.album: [album('album-1', 'missing-artist')],
    });

    final inventory = await CloudRecoveryInventoryService(
      reader: reader,
    ).inspect(userId: 'user-a');

    expect(inventory.activeCount(CloudDataEntity.album), 1);
    expect(inventory.hasDependencyIssues, isTrue);
    expect(
      inventory.dependencyIssues.single.kind,
      CloudRecoveryDependencyIssueKind.missingReference,
    );
    expect(inventory.dependencyIssues.single.referencedId, 'missing-artist');
  });

  test('integrated inventory accepts present parent records', () async {
    final reader = DependencyTestReader({
      CloudDataEntity.artist: [artist('artist-1')],
      CloudDataEntity.album: [album('album-1', 'artist-1')],
    });

    final inventory = await CloudRecoveryInventoryService(
      reader: reader,
    ).inspect(userId: 'user-a');

    expect(inventory.totalActive, 2);
    expect(inventory.hasDependencyIssues, isFalse);
  });

  test('dependency validation works across paginated records', () async {
    final reader = DependencyTestReader({
      CloudDataEntity.artist: [artist('artist-1'), artist('artist-2')],
      CloudDataEntity.album: [album('album-1', 'artist-2')],
    });

    final inventory = await CloudRecoveryInventoryService(
      reader: reader,
    ).inspect(userId: 'user-a', pageSize: 1);

    expect(inventory.totalActive, 3);
    expect(inventory.hasDependencyIssues, isFalse);
    expect(reader.reads, greaterThan(CloudDataEntity.values.length));
  });

  test('dependency findings cannot be modified', () async {
    final inventory = await CloudRecoveryInventoryService(
      reader: DependencyTestReader({
        CloudDataEntity.album: [album('album-1', 'missing-artist')],
      }),
    ).inspect(userId: 'user-a');

    expect(() => inventory.dependencyIssues.clear(), throwsUnsupportedError);
  });
}
