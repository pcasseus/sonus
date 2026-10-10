import '../../../library/domain/entities/album.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/repositories/album_edition_track_repository.dart';
import '../../../library/domain/entities/album_edition_track.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../domain/models/cloud_records.dart';
import 'sync_mutation_context.dart';

class InboundCloudRecordApplier {
  const InboundCloudRecordApplier();

  Future<void> apply({
    required CloudOwnedRecord record,
    required SyncMutationContext context,
  }) async {
    if (record.isDeleted) {
      throw StateError(
        'Inbound tombstone reconciliation is not implemented yet.',
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

      case CloudArtworkAssetRecord():
        throw StateError(
          'Inbound artwork requires Storage download before reconciliation.',
        );

      default:
        throw ArgumentError.value(
          record,
          'record',
          'Unsupported cloud record type.',
        );
    }
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
