import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_inventory_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

final timestamp = DateTime.utc(2026, 10, 21);

CloudArtistRecord artist(
  String id, {
  String userId = 'user-a',
  bool deleted = false,
}) {
  return CloudArtistRecord(
    id: id,
    userId: userId,
    name: id,
    canonicalName: id,
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: deleted ? timestamp : null,
  );
}

class FakeCloudReader implements CloudSyncReader {
  FakeCloudReader(this.records);

  final Map<CloudDataEntity, List<CloudOwnedRecord>> records;
  int readCount = 0;

  @override
  Future<CloudSyncPage> readPage({
    required String userId,
    required CloudDataEntity entityType,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
    required int limit,
  }) async {
    readCount++;

    final sorted =
        List<CloudOwnedRecord>.of(
          records[entityType] ?? const <CloudOwnedRecord>[],
        )..sort((a, b) {
          final dateComparison = a.updatedAt.compareTo(b.updatedAt);
          return dateComparison != 0 ? dateComparison : a.id.compareTo(b.id);
        });

    final remaining = sorted.where((record) {
      if (after == null) return true;

      final dateComparison = record.updatedAt.compareTo(after.serverUpdatedAt);

      return dateComparison > 0 ||
          (dateComparison == 0 && record.id.compareTo(after.id) > 0);
    }).toList();

    final selected = remaining.take(limit).toList();

    return CloudSyncPage(
      items: [
        for (final record in selected)
          CloudSyncItem(record: record, serverUpdatedAt: record.updatedAt),
      ],
      hasMore: remaining.length > selected.length,
    );
  }
}

class RepeatingCloudReader implements CloudSyncReader {
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

    return CloudSyncPage(
      items: [
        CloudSyncItem(record: artist('artist-1'), serverUpdatedAt: timestamp),
      ],
      hasMore: true,
    );
  }
}

void main() {
  test('distinguishes an empty cloud account', () async {
    final inventory = await CloudRecoveryInventoryService(
      reader: FakeCloudReader({}),
    ).inspect(userId: 'user-a');

    expect(inventory.hasCloudRecords, isFalse);
    expect(inventory.totalActive, 0);
    expect(inventory.totalTombstones, 0);
    expect(inventory.activeCounts.length, CloudDataEntity.values.length);
  });

  test('counts active cloud records', () async {
    final inventory = await CloudRecoveryInventoryService(
      reader: FakeCloudReader({
        CloudDataEntity.artist: [artist('artist-1'), artist('artist-2')],
      }),
    ).inspect(userId: 'user-a');

    expect(inventory.activeCount(CloudDataEntity.artist), 2);
    expect(inventory.totalActive, 2);
    expect(inventory.hasCloudRecords, isTrue);
  });

  test('counts tombstones separately', () async {
    final inventory = await CloudRecoveryInventoryService(
      reader: FakeCloudReader({
        CloudDataEntity.artist: [
          artist('artist-1'),
          artist('artist-2', deleted: true),
        ],
      }),
    ).inspect(userId: 'user-a');

    expect(inventory.activeCount(CloudDataEntity.artist), 1);
    expect(inventory.tombstoneCount(CloudDataEntity.artist), 1);
  });

  test('reads multiple pages without duplicating records', () async {
    final reader = FakeCloudReader({
      CloudDataEntity.artist: [
        artist('artist-3'),
        artist('artist-1'),
        artist('artist-2'),
      ],
    });

    final inventory = await CloudRecoveryInventoryService(
      reader: reader,
    ).inspect(userId: 'user-a', pageSize: 1);

    expect(inventory.activeCount(CloudDataEntity.artist), 3);
    expect(reader.readCount, greaterThan(CloudDataEntity.values.length));
  });

  test('rejects records owned by a different user', () async {
    final service = CloudRecoveryInventoryService(
      reader: FakeCloudReader({
        CloudDataEntity.artist: [artist('artist-1', userId: 'user-b')],
      }),
    );

    await expectLater(service.inspect(userId: 'user-a'), throwsStateError);
  });

  test('rejects records from the wrong entity category', () async {
    final service = CloudRecoveryInventoryService(
      reader: FakeCloudReader({
        CloudDataEntity.artist: [
          CloudAlbumRecord(
            id: 'album-1',
            userId: 'user-a',
            artistId: 'artist-1',
            title: 'Album',
            canonicalTitle: 'album',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
      }),
    );

    await expectLater(service.inspect(userId: 'user-a'), throwsStateError);
  });

  test('rejects pagination that repeatedly returns the same record', () async {
    final service = CloudRecoveryInventoryService(
      reader: RepeatingCloudReader(),
    );

    await expectLater(
      service.inspect(userId: 'user-a', pageSize: 1),
      throwsStateError,
    );
  });

  test('rejects blank account identifiers', () async {
    final reader = FakeCloudReader({});
    final service = CloudRecoveryInventoryService(reader: reader);

    await expectLater(service.inspect(userId: '   '), throwsArgumentError);

    expect(reader.readCount, 0);
  });
}
