import '../../../library/domain/entities/album.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/repositories/album_edition_track_repository.dart';
import '../../../library/domain/entities/album_edition_track.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/sync_data_contract.dart';
import 'sync_mutation_context.dart';

/// The local effect of reconciling one verified cloud revision.
class InboundApplyResult {
  const InboundApplyResult.applied() : deferralReason = null;

  const InboundApplyResult.deferred(InboundDeferralReason this.deferralReason);

  /// Non-null when local data was left untouched and the revision must
  /// be durably recorded for replay.
  final InboundDeferralReason? deferralReason;

  bool get isDeferred => deferralReason != null;
}

class InboundCloudRecordApplier {
  const InboundCloudRecordApplier();

  Future<InboundApplyResult> apply({
    required CloudOwnedRecord record,
    required SyncMutationContext context,
  }) async {
    if (record.isDeleted) {
      // A tombstone for an entity this device never had is already
      // reflected locally. Local deletion is not implemented, so any
      // existing entity is left intact and the tombstone is deferred.
      return await _existsLocally(record, context)
          ? const InboundApplyResult.deferred(
              InboundDeferralReason.tombstoneRequiresLocalDeletion,
            )
          : const InboundApplyResult.applied();
    }

    if (record is CloudArtworkAssetRecord) {
      // Artwork bytes are not downloaded yet. A local asset with the same
      // id already holds them; otherwise the revision is deferred.
      return await context.artworkAssetRepository.getById(record.id) == null
          ? const InboundApplyResult.deferred(
              InboundDeferralReason.artworkDownloadRequired,
            )
          : const InboundApplyResult.applied();
    }

    // A child must never be applied ahead of a parent that is missing
    // locally or whose newer revision is still deferred.
    final parentReason = await _unavailableParentReason(record, context);

    if (parentReason != null) {
      return InboundApplyResult.deferred(parentReason);
    }

    // Local artwork foreign keys would reject the write.
    if (!await _referencedArtworkExists(record, context)) {
      return const InboundApplyResult.deferred(
        InboundDeferralReason.missingLocalArtwork,
      );
    }

    switch (record) {
      case CloudArtistRecord():
        await _applyArtist(record, context);

      case CloudAlbumRecord():
        await _applyAlbum(record, context);

      case CloudAlbumEditionRecord():
        await _applyAlbumEdition(record, context);

      case CloudSongRecord():
        await _applySong(record, context);

      default:
        throw ArgumentError.value(
          record,
          'record',
          'Unsupported cloud record type.',
        );
    }

    return const InboundApplyResult.applied();
  }

  Future<bool> _existsLocally(
    CloudOwnedRecord record,
    SyncMutationContext context,
  ) async {
    final Object? existing = switch (record) {
      CloudArtworkAssetRecord() => await context.artworkAssetRepository.getById(
        record.id,
      ),
      CloudArtistRecord() => await context.artistRepository.getById(record.id),
      CloudAlbumRecord() => await context.albumRepository.getById(record.id),
      CloudAlbumEditionRecord() => await context.albumEditionRepository.getById(
        record.id,
      ),
      CloudSongRecord() => await context.songRepository.getById(record.id),
      _ => throw ArgumentError.value(
        record,
        'record',
        'Unsupported cloud record type.',
      ),
    };

    return existing != null;
  }

  Future<InboundDeferralReason?> _unavailableParentReason(
    CloudOwnedRecord record,
    SyncMutationContext context,
  ) async {
    final parents = switch (record) {
      CloudAlbumRecord() => [(CloudDataEntity.artist, record.artistId)],
      CloudAlbumEditionRecord() => [(CloudDataEntity.album, record.albumId)],
      CloudSongRecord() => [
        (CloudDataEntity.artist, record.artistId),
        (CloudDataEntity.album, record.albumId),
        (CloudDataEntity.albumEdition, record.albumEditionId),
      ],
      _ => const <(CloudDataEntity, String)>[],
    };

    for (final (entityType, entityId) in parents) {
      final Object? parent = switch (entityType) {
        CloudDataEntity.artist => await context.artistRepository.getById(
          entityId,
        ),
        CloudDataEntity.album => await context.albumRepository.getById(
          entityId,
        ),
        CloudDataEntity.albumEdition =>
          await context.albumEditionRepository.getById(entityId),
        _ => throw StateError('Unsupported parent type: ${entityType.name}'),
      };

      if (parent == null) {
        return InboundDeferralReason.missingLocalParent;
      }

      final deferral = await context.inboundDeferredRecordRepository
          ?.getDeferral(
            userId: record.userId,
            entityType: entityType,
            entityId: entityId,
          );

      if (deferral != null) {
        return InboundDeferralReason.parentDeferred;
      }
    }

    return null;
  }

  Future<bool> _referencedArtworkExists(
    CloudOwnedRecord record,
    SyncMutationContext context,
  ) async {
    final artworkIds = switch (record) {
      CloudArtistRecord() => [
        record.headerArtworkId,
        record.topArtistsArtworkId,
      ],
      CloudAlbumEditionRecord() => [record.artworkId],
      CloudSongRecord() => [record.artworkId],
      _ => const <String?>[],
    };

    for (final artworkId in artworkIds) {
      if (artworkId != null &&
          await context.artworkAssetRepository.getById(artworkId) == null) {
        return false;
      }
    }

    return true;
  }

  Future<void> _applyArtist(
    CloudArtistRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Artist(
      id: record.id,
      name: record.name,
      canonicalName: record.canonicalName,
      headerArtworkId: record.headerArtworkId,
      topArtistsArtworkId: record.topArtistsArtworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.artistRepository.getById(record.id);

    if (existing == null) {
      await context.artistRepository.create(entity);
    } else {
      await context.artistRepository.save(entity);
    }

    await _restoreMetadataFieldStates(
      entityType: MetadataEntityType.artist,
      entityId: record.id,
      cloudStates: record.metadataFieldStates,
      context: context,
    );
  }

  Future<void> _applyAlbum(
    CloudAlbumRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Album(
      id: record.id,
      artistId: record.artistId,
      title: record.title,
      canonicalTitle: record.canonicalTitle,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.albumRepository.getById(record.id);

    if (existing == null) {
      await context.albumRepository.create(entity);
    } else {
      await context.albumRepository.save(entity);
    }

    await _restoreMetadataFieldStates(
      entityType: MetadataEntityType.album,
      entityId: record.id,
      cloudStates: record.metadataFieldStates,
      context: context,
    );
  }

  Future<void> _applyAlbumEdition(
    CloudAlbumEditionRecord record,
    SyncMutationContext context,
  ) async {
    final entity = AlbumEdition(
      id: record.id,
      albumId: record.albumId,
      title: record.title,
      type: _albumEditionType(record.type),
      isPrimary: record.isPrimary,
      releaseDate: record.releaseDate,
      genre: record.genre,
      artworkId: record.artworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.albumEditionRepository.getById(record.id);

    if (existing == null) {
      await context.albumEditionRepository.create(entity);
    } else {
      await context.albumEditionRepository.save(entity);
    }

    await _restoreMetadataFieldStates(
      entityType: MetadataEntityType.albumEdition,
      entityId: record.id,
      cloudStates: record.metadataFieldStates,
      context: context,
    );
  }

  Future<void> _applySong(
    CloudSongRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Song(
      id: record.id,
      artistId: record.artistId,
      albumId: record.albumId,
      albumEditionId: record.albumEditionId,
      title: record.title,
      canonicalTitle: record.canonicalTitle,
      trackNumber: record.trackNumber,
      discNumber: record.discNumber,
      durationSeconds: record.durationSeconds,
      isSingle: record.isSingle,
      isBlocked: record.isBlocked,
      featuredArtists: record.featuredArtists,
      versionLabel: record.versionLabel,
      versionCharacteristics: record.versionCharacteristics
          .map(SongVersionCharacteristic.values.byName)
          .toList(growable: false),
      releaseStatus: SongReleaseStatus.values.byName(record.releaseStatus),
      isLeak: record.isLeak,
      artworkId: record.artworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.songRepository.getById(record.id);

    final membershipRepository = context.albumEditionTrackRepository;
    final targetMemberships = await membershipRepository.getByEditionId(
      entity.albumEditionId,
    );

    AlbumEditionTrack? targetMembership;

    for (final membership in targetMemberships) {
      if (membership.songId == entity.id) {
        targetMembership = membership;
        break;
      }
    }

    final effectiveEntity =
        targetMembership?.numberingAuthority ==
            AlbumEditionTrackAuthority.manual
        ? entity.copyWith(
            discNumber: targetMembership!.discNumber,
            trackNumber: targetMembership.trackNumber,
          )
        : entity;

    if (existing == null) {
      await context.songRepository.create(effectiveEntity);
    } else {
      await context.songRepository.save(effectiveEntity);
    }

    await _reconcileSongCompatibilityMembership(
      membershipRepository: membershipRepository,
      previousSong: existing,
      incomingSong: effectiveEntity,
      targetMemberships: targetMemberships,
      targetMembership: targetMembership,
    );

    await _restoreMetadataFieldStates(
      entityType: MetadataEntityType.song,
      entityId: record.id,
      cloudStates: record.metadataFieldStates,
      context: context,
    );
  }

  Future<void> _reconcileSongCompatibilityMembership({
    required AlbumEditionTrackRepository membershipRepository,
    required Song? previousSong,
    required Song incomingSong,
    required List<AlbumEditionTrack> targetMemberships,
    required AlbumEditionTrack? targetMembership,
  }) async {
    if (targetMembership == null) {
      final nextSortPosition = targetMemberships.isEmpty
          ? 0
          : targetMemberships
                    .map((membership) => membership.sortPosition)
                    .reduce((left, right) => left > right ? left : right) +
                1;

      await membershipRepository.create(
        AlbumEditionTrack(
          albumEditionId: incomingSong.albumEditionId,
          songId: incomingSong.id,
          discNumber: incomingSong.discNumber,
          trackNumber: incomingSong.trackNumber,
          sortPosition: nextSortPosition,
          createdAt: incomingSong.createdAt,
          updatedAt: incomingSong.updatedAt,
        ),
      );
    } else {
      final placementChanged =
          targetMembership.discNumber != incomingSong.discNumber ||
          targetMembership.trackNumber != incomingSong.trackNumber;

      if (placementChanged &&
          targetMembership.numberingAuthority !=
              AlbumEditionTrackAuthority.manual) {
        await membershipRepository.save(
          targetMembership.copyWith(
            discNumber: incomingSong.discNumber,
            trackNumber: incomingSong.trackNumber,
            updatedAt: incomingSong.updatedAt,
          ),
        );
      }
    }

    if (previousSong == null) {
      return;
    }

    final albumChanged = previousSong.albumId != incomingSong.albumId;

    if (!albumChanged ||
        previousSong.albumEditionId == incomingSong.albumEditionId) {
      return;
    }

    final previousMemberships = await membershipRepository.getByEditionId(
      previousSong.albumEditionId,
    );

    final hadPreviousCompatibilityMembership = previousMemberships.any(
      (membership) => membership.songId == incomingSong.id,
    );

    if (hadPreviousCompatibilityMembership) {
      await membershipRepository.delete(
        editionId: previousSong.albumEditionId,
        songId: incomingSong.id,
      );
    }
  }

  Future<void> _restoreMetadataFieldStates({
    required MetadataEntityType entityType,
    required String entityId,
    required List<CloudMetadataFieldState>? cloudStates,
    required SyncMutationContext context,
  }) async {
    // Null means this cloud row predates provenance sync.
    // Preserve any local provenance already present.
    if (cloudStates == null) {
      return;
    }

    final repository = context.metadataFieldStateRepository;

    if (repository == null) {
      throw StateError(
        'Metadata field state repository is required for inbound provenance.',
      );
    }

    // Any non-null cloud snapshot is authoritative, including [].
    await repository.deleteByEntity(entityType: entityType, entityId: entityId);

    for (final cloudState in cloudStates) {
      await repository.save(
        MetadataFieldState(
          entityType: entityType,
          entityId: entityId,
          fieldName: cloudState.fieldName,
          authority: MetadataAuthority.values.byName(cloudState.authority),
          source: MetadataProvenanceSource.values.byName(cloudState.source),
          sourceReference: cloudState.sourceReference,
          updatedAt: cloudState.updatedAt,
        ),
      );
    }
  }

  AlbumEditionType _albumEditionType(String value) {
    return switch (value) {
      'standard' => AlbumEditionType.standard,
      'deluxe' => AlbumEditionType.deluxe,
      'expanded' => AlbumEditionType.expanded,
      'anniversary' => AlbumEditionType.anniversary,
      'remaster' => AlbumEditionType.remaster,
      'other' => AlbumEditionType.other,
      _ => throw StateError('Unsupported album edition type: $value'),
    };
  }
}
