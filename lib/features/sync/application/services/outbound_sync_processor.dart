import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/repositories/metadata_field_state_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../application/mappers/cloud_record_mapper.dart';
import '../../application/repositories/local_sync_repository.dart';
import '../../application/repositories/cloud_revision_baseline_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artwork_storage.dart';
import 'cloud_sync_gateway.dart';

/// Handles an explicit artist mutation and owns its acknowledgement.
typedef PushArtistMutation =
    Future<void> Function({
      required String userId,
      required SyncOutboxEntry entry,
      required CloudArtistRecord artist,
    });

/// Ensures a referenced cloud artist exists without acknowledging
/// an explicit artist outbox mutation.
typedef EnsureArtistDependency =
    Future<void> Function({
      required String userId,
      required CloudArtistRecord artist,
    });

/// Handles a guarded artist deletion and its local acknowledgement.
typedef PushArtistDeletion =
    Future<void> Function({
      required String userId,
      required SyncOutboxEntry entry,
    });

/// Reconciles durable artist receipts before reading the regular outbox.
typedef RecoverArtistWrites = Future<void> Function(String userId);

class OutboundSyncProcessor {
  OutboundSyncProcessor({
    required this.localSyncRepository,
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.songRepository,
    required this.metadataFieldStateRepository,
    required this.artworkAssetRepository,
    required this.cloudArtworkStorage,
    required this.cloudSyncGateway,
    this.cloudRevisionBaselineRepository,
    this.pushArtistMutation,
    this.pushArtistDeletion,
    this.ensureArtistDependency,
    this.recoverArtistWrites,
  });

  final LocalSyncRepository localSyncRepository;
  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;
  final MetadataFieldStateRepository metadataFieldStateRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final CloudArtworkStorage cloudArtworkStorage;
  final CloudSyncGateway cloudSyncGateway;
  final CloudRevisionBaselineRepository? cloudRevisionBaselineRepository;
  final PushArtistMutation? pushArtistMutation;
  final PushArtistDeletion? pushArtistDeletion;
  final EnsureArtistDependency? ensureArtistDependency;
  final RecoverArtistWrites? recoverArtistWrites;

  // Serialize full outbound runs on this processor instance.
  // Recover from failure so subsequent retries can execute.
  Future<void> _pendingPushRun = Future<void>.value();

  Future<void> pushPending(String userId) {
    final current = _pendingPushRun.then((_) => _pushPendingOnce(userId));

    _pendingPushRun = current.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );

    return current;
  }

  Future<void> _pushPendingOnce(String userId) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    if ((pushArtistMutation == null) !=
        (cloudRevisionBaselineRepository == null)) {
      throw StateError(
        'Guarded artist sync requires coordinator and revision baselines.',
      );
    }

    if (pushArtistDeletion != null &&
        (pushArtistMutation == null ||
            cloudRevisionBaselineRepository == null)) {
      throw StateError(
        'Guarded artist deletion requires guarded artist mutations '
        'and revision baselines.',
      );
    }

    if (ensureArtistDependency != null && pushArtistMutation == null) {
      throw StateError(
        'Artist dependency creation requires guarded artist mutations.',
      );
    }

    final recover = recoverArtistWrites;

    if (recover != null) {
      if (pushArtistMutation == null ||
          pushArtistDeletion == null ||
          cloudRevisionBaselineRepository == null) {
        throw StateError(
          'Artist recovery requires guarded mutation, deletion, '
          'and revision baseline handlers.',
        );
      }

      // The journal is authoritative until its receipt is reconciled.
      // A recovery failure must stop all ordinary outbound writes.
      await recover(trimmedUserId);
    }

    final pending = await localSyncRepository.getPending(trimmedUserId);
    final ordered = [...pending]..sort(_compareEntries);

    final ensuredArtworkIds = <String>{};
    final ensuredArtistIds = <String>{};
    final ensuredAlbumIds = <String>{};
    final ensuredAlbumEditionIds = <String>{};
    final ensuredSongIds = <String>{};

    for (final entry in ordered) {
      if (entry.userId != trimmedUserId) {
        throw StateError(
          'Outbox entry ${entry.id} does not belong to user $trimmedUserId.',
        );
      }

      switch (entry.operation) {
        case SyncOutboxOperation.upsert:
          await _pushUpsert(
            entry,
            userId: trimmedUserId,
            ensuredArtworkIds: ensuredArtworkIds,
            ensuredArtistIds: ensuredArtistIds,
            ensuredAlbumIds: ensuredAlbumIds,
            ensuredAlbumEditionIds: ensuredAlbumEditionIds,
            ensuredSongIds: ensuredSongIds,
          );

        case SyncOutboxOperation.delete:
          final guardedDeletion = pushArtistDeletion;

          if (entry.entityType == CloudDataEntity.artist &&
              guardedDeletion != null) {
            await guardedDeletion(userId: trimmedUserId, entry: entry);
          } else {
            await cloudSyncGateway.markDeleted(
              userId: trimmedUserId,
              entityType: entry.entityType,
              entityId: entry.entityId,
              deletedAt: entry.updatedAt,
            );
          }
      }

      final guardedArtistMutation =
          pushArtistMutation != null &&
          entry.entityType == CloudDataEntity.artist &&
          entry.operation == SyncOutboxOperation.upsert;

      final guardedArtistDeletion =
          pushArtistDeletion != null &&
          entry.entityType == CloudDataEntity.artist &&
          entry.operation == SyncOutboxOperation.delete;

      if (!guardedArtistMutation && !guardedArtistDeletion) {
        await localSyncRepository.markProcessed(
          userId: trimmedUserId,
          outboxEntryId: entry.id,
          expectedRevision: entry.mutationRevision,
          expectedOperation: entry.operation,
        );
      }
    }
  }

  Future<void> _pushUpsert(
    SyncOutboxEntry entry, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    required Set<String> ensuredSongIds,
  }) async {
    switch (entry.entityType) {
      case CloudDataEntity.artworkAsset:
        await _ensureArtwork(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
        );

      case CloudDataEntity.artist:
        await _ensureArtist(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          explicitEntry: entry,
        );

      case CloudDataEntity.album:
        await _ensureAlbum(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
        );

      case CloudDataEntity.albumEdition:
        await _ensureAlbumEdition(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
        );

      case CloudDataEntity.song:
        await _ensureSong(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
          ensuredSongIds: ensuredSongIds,
        );
    }
  }

  Future<void> _ensureArtwork(
    String artworkId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
  }) async {
    final normalizedArtworkId = artworkId.trim();

    if (normalizedArtworkId.isEmpty ||
        ensuredArtworkIds.contains(normalizedArtworkId)) {
      return;
    }

    final entity = await artworkAssetRepository.getById(normalizedArtworkId);

    if (entity == null) {
      throw StateError(
        'Artwork asset $normalizedArtworkId is missing for sync.',
      );
    }

    final storageObjectKey = await cloudArtworkStorage.upload(
      userId: userId,
      artworkAsset: entity,
    );

    await cloudSyncGateway.upsert(
      CloudRecordMapper.artworkAsset(
        artworkAsset: entity,
        userId: userId,
        storageObjectKey: storageObjectKey,
      ),
    );

    ensuredArtworkIds.add(normalizedArtworkId);
  }

  Future<void> _ensureOptionalArtwork(
    String? artworkId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
  }) async {
    final normalizedArtworkId = artworkId?.trim();

    if (normalizedArtworkId == null || normalizedArtworkId.isEmpty) {
      return;
    }

    await _ensureArtwork(
      normalizedArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );
  }

  Future<void> _ensureArtist(
    String artistId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedArtistId = artistId.trim();

    if (explicitEntry == null &&
        ensuredArtistIds.contains(normalizedArtistId)) {
      return;
    }

    final entity = await artistRepository.getById(normalizedArtistId);

    if (entity == null) {
      throw StateError('Artist $normalizedArtistId is missing for sync.');
    }

    await _ensureOptionalArtwork(
      entity.headerArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    await _ensureOptionalArtwork(
      entity.topArtistsArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.artist,
      entityId: normalizedArtistId,
    );

    final cloudArtist = CloudRecordMapper.artist(
      artist: entity,
      userId: userId,
      metadataFieldStates: metadataFieldStates,
    );

    final guardedPusher = pushArtistMutation;

    if (guardedPusher == null) {
      // Legacy behavior remains in effect until production wiring changes.
      await cloudSyncGateway.upsert(cloudArtist);
    } else if (explicitEntry != null) {
      // The coordinator commits both the cloud revision and acknowledgement.
      await guardedPusher(
        userId: userId,
        entry: explicitEntry,
        artist: cloudArtist,
      );
    } else {
      // A dependency cannot unconditionally overwrite an artist.
      final dependencyEnsurer = ensureArtistDependency;

      if (dependencyEnsurer != null) {
        await dependencyEnsurer(userId: userId, artist: cloudArtist);
      } else {
        // Compatibility path for existing guarded processor tests.
        final baselines = cloudRevisionBaselineRepository;

        if (baselines == null) {
          throw StateError('Missing cloud revision baseline repository.');
        }

        final revision = await baselines.getRevision(
          userId: userId,
          entityType: CloudDataEntity.artist,
          entityId: normalizedArtistId,
        );

        if (revision == null || revision < 1) {
          throw StateError(
            'Artist $normalizedArtistId has no reconciled cloud baseline. '
            'Dependency upload deferred.',
          );
        }
      }
    }

    ensuredArtistIds.add(normalizedArtistId);
  }

  Future<void> _ensureAlbum(
    String albumId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
  }) async {
    final normalizedAlbumId = albumId.trim();

    if (ensuredAlbumIds.contains(normalizedAlbumId)) {
      return;
    }

    final entity = await albumRepository.getById(normalizedAlbumId);

    if (entity == null) {
      throw StateError('Album $normalizedAlbumId is missing for sync.');
    }

    await _ensureArtist(
      entity.artistId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.album,
      entityId: normalizedAlbumId,
    );

    await cloudSyncGateway.upsert(
      CloudRecordMapper.album(
        album: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
      ),
    );

    ensuredAlbumIds.add(normalizedAlbumId);
  }

  Future<void> _ensureAlbumEdition(
    String albumEditionId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
  }) async {
    final normalizedEditionId = albumEditionId.trim();

    if (ensuredAlbumEditionIds.contains(normalizedEditionId)) {
      return;
    }

    final entity = await albumEditionRepository.getById(normalizedEditionId);

    if (entity == null) {
      throw StateError(
        'Album edition $normalizedEditionId is missing for sync.',
      );
    }

    await _ensureAlbum(
      entity.albumId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
    );

    await _ensureOptionalArtwork(
      entity.artworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: normalizedEditionId,
    );

    await cloudSyncGateway.upsert(
      CloudRecordMapper.albumEdition(
        albumEdition: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
      ),
    );

    ensuredAlbumEditionIds.add(normalizedEditionId);
  }

  Future<void> _ensureSong(
    String songId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    required Set<String> ensuredSongIds,
  }) async {
    final normalizedSongId = songId.trim();

    if (ensuredSongIds.contains(normalizedSongId)) {
      return;
    }

    final entity = await songRepository.getById(normalizedSongId);

    if (entity == null) {
      throw StateError('Song $normalizedSongId is missing for sync.');
    }

    await _ensureArtist(
      entity.artistId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
    );

    await _ensureAlbum(
      entity.albumId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
    );

    await _ensureAlbumEdition(
      entity.albumEditionId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
      ensuredAlbumEditionIds: ensuredAlbumEditionIds,
    );

    await _ensureOptionalArtwork(
      entity.artworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.song,
      entityId: normalizedSongId,
    );

    await cloudSyncGateway.upsert(
      CloudRecordMapper.song(
        song: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
      ),
    );

    ensuredSongIds.add(normalizedSongId);
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
