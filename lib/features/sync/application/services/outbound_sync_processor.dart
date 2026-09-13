import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../application/mappers/cloud_record_mapper.dart';
import '../../application/repositories/local_sync_repository.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artwork_storage.dart';
import 'cloud_sync_gateway.dart';

class OutboundSyncProcessor {
  const OutboundSyncProcessor({
    required this.localSyncRepository,
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.songRepository,
    required this.artworkAssetRepository,
    required this.cloudArtworkStorage,
    required this.cloudSyncGateway,
  });

  final LocalSyncRepository localSyncRepository;
  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final CloudArtworkStorage cloudArtworkStorage;
  final CloudSyncGateway cloudSyncGateway;

  Future<void> pushPending(String userId) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    final pending = await localSyncRepository.getPending(trimmedUserId);
    final ordered = [...pending]..sort(_compareEntries);

    for (final entry in ordered) {
      if (entry.userId != trimmedUserId) {
        throw StateError(
          'Outbox entry ${entry.id} does not belong to user $trimmedUserId.',
        );
      }

      switch (entry.operation) {
        case SyncOutboxOperation.upsert:
          await _pushUpsert(entry);

        case SyncOutboxOperation.delete:
          await cloudSyncGateway.markDeleted(
            userId: trimmedUserId,
            entityType: entry.entityType,
            entityId: entry.entityId,
            deletedAt: entry.updatedAt,
          );
      }

      await localSyncRepository.markProcessed(
        userId: trimmedUserId,
        outboxEntryId: entry.id,
      );
    }
  }

  Future<void> _pushUpsert(SyncOutboxEntry entry) async {
    switch (entry.entityType) {
      case CloudDataEntity.artworkAsset:
        final entity = await artworkAssetRepository.getById(entry.entityId);

        if (entity == null) {
          throw StateError(
            'Artwork asset ${entry.entityId} is missing for pending sync upsert.',
          );
        }

        final storageObjectKey = await cloudArtworkStorage.upload(
          userId: entry.userId,
          artworkAsset: entity,
        );

        await cloudSyncGateway.upsert(
          CloudRecordMapper.artworkAsset(
            artworkAsset: entity,
            userId: entry.userId,
            storageObjectKey: storageObjectKey,
          ),
        );

      case CloudDataEntity.artist:
        final entity = await artistRepository.getById(entry.entityId);

        if (entity == null) {
          throw StateError(
            'Artist ${entry.entityId} is missing for pending sync upsert.',
          );
        }

        await cloudSyncGateway.upsert(
          CloudRecordMapper.artist(artist: entity, userId: entry.userId),
        );

      case CloudDataEntity.album:
        final entity = await albumRepository.getById(entry.entityId);

        if (entity == null) {
          throw StateError(
            'Album ${entry.entityId} is missing for pending sync upsert.',
          );
        }

        await cloudSyncGateway.upsert(
          CloudRecordMapper.album(album: entity, userId: entry.userId),
        );

      case CloudDataEntity.albumEdition:
        final entity = await albumEditionRepository.getById(entry.entityId);

        if (entity == null) {
          throw StateError(
            'Album edition ${entry.entityId} is missing for pending sync upsert.',
          );
        }

        await cloudSyncGateway.upsert(
          CloudRecordMapper.albumEdition(
            albumEdition: entity,
            userId: entry.userId,
          ),
        );

      case CloudDataEntity.song:
        final entity = await songRepository.getById(entry.entityId);

        if (entity == null) {
          throw StateError(
            'Song ${entry.entityId} is missing for pending sync upsert.',
          );
        }

        await cloudSyncGateway.upsert(
          CloudRecordMapper.song(song: entity, userId: entry.userId),
        );
    }
  }

  int _compareEntries(SyncOutboxEntry left, SyncOutboxEntry right) {
    final leftRank = _dependencyRank(left.entityType);
    final rightRank = _dependencyRank(right.entityType);

    final rankComparison = leftRank.compareTo(rightRank);
    if (rankComparison != 0) {
      return rankComparison;
    }

    final createdComparison = left.createdAt.compareTo(right.createdAt);
    if (createdComparison != 0) {
      return createdComparison;
    }

    return left.id.compareTo(right.id);
  }

  int _dependencyRank(CloudDataEntity entityType) {
    return switch (entityType) {
      CloudDataEntity.artworkAsset => 0,
      CloudDataEntity.artist => 1,
      CloudDataEntity.album => 2,
      CloudDataEntity.albumEdition => 3,
      CloudDataEntity.song => 4,
    };
  }
}
