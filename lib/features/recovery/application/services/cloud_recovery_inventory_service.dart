import '../../../sync/application/services/cloud_sync_reader.dart';
import '../../../sync/domain/models/cloud_records.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../models/cloud_recovery_inventory.dart';
import 'cloud_recovery_dependency_validator.dart';

class CloudRecoveryInventoryService {
  const CloudRecoveryInventoryService({required this.reader});

  final CloudSyncReader reader;

  Future<CloudRecoveryInventory> inspect({
    required String userId,
    int pageSize = 100,
  }) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }

    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }

    final activeCounts = <CloudDataEntity, int>{};
    final tombstoneCounts = <CloudDataEntity, int>{};
    final collectedRecords = <CloudOwnedRecord>[];

    for (final entityType in CloudDataEntity.values) {
      var active = 0;
      var tombstones = 0;
      CloudSyncPosition? after;
      final seenIds = <String>{};

      while (true) {
        final page = await reader.readPage(
          userId: normalizedUserId,
          entityType: entityType,
          after: after,
          limit: pageSize,
        );

        if (page.items.isEmpty && page.hasMore) {
          throw StateError(
            'Cloud inventory pagination did not advance for '
            '${entityType.name}.',
          );
        }

        var lastPosition = after;

        for (final item in page.items) {
          final record = item.record;

          if (record.userId != normalizedUserId) {
            throw StateError(
              'Cloud inventory returned a record owned by another user.',
            );
          }

          if (!_matchesType(entityType, record)) {
            throw StateError(
              'Cloud inventory returned the wrong record type for '
              '${entityType.name}.',
            );
          }

          if (!seenIds.add(record.id)) {
            throw StateError(
              'Cloud inventory returned duplicate record ${record.id}.',
            );
          }

          final position = CloudSyncPosition(
            serverUpdatedAt: item.serverUpdatedAt,
            id: record.id,
          );

          if (lastPosition != null && !_isAfter(position, lastPosition)) {
            throw StateError(
              'Cloud inventory returned records out of pagination order.',
            );
          }

          lastPosition = position;
          collectedRecords.add(record);

          if (record.isDeleted) {
            tombstones++;
          } else {
            active++;
          }
        }

        if (!page.hasMore) {
          break;
        }

        after = lastPosition;
      }

      activeCounts[entityType] = active;
      tombstoneCounts[entityType] = tombstones;
    }

    return CloudRecoveryInventory(
      activeCounts: activeCounts,
      tombstoneCounts: tombstoneCounts,
      dependencyIssues: const CloudRecoveryDependencyValidator().validate(
        collectedRecords,
      ),
    );
  }

  bool _isAfter(CloudSyncPosition candidate, CloudSyncPosition previous) {
    final comparison = candidate.serverUpdatedAt.compareTo(
      previous.serverUpdatedAt,
    );

    return comparison > 0 ||
        (comparison == 0 && candidate.id.compareTo(previous.id) > 0);
  }

  bool _matchesType(CloudDataEntity entityType, CloudOwnedRecord record) {
    return switch (entityType) {
      CloudDataEntity.artist => record is CloudArtistRecord,
      CloudDataEntity.album => record is CloudAlbumRecord,
      CloudDataEntity.albumEdition => record is CloudAlbumEditionRecord,
      CloudDataEntity.song => record is CloudSongRecord,
      CloudDataEntity.artworkAsset => record is CloudArtworkAssetRecord,
    };
  }
}
