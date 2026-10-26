import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/services/metadata_field_state_service.dart';

class AlbumProfileEditResult {
  const AlbumProfileEditResult({
    required this.album,
    required this.primaryEdition,
    required this.albumChanged,
    required this.primaryEditionChanged,
  });

  final Album album;
  final AlbumEdition primaryEdition;
  final bool albumChanged;
  final bool primaryEditionChanged;

  bool get changed => albumChanged || primaryEditionChanged;
}

class AlbumProfileEditingService {
  const AlbumProfileEditingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  /// Records that the user keeps the release's current owner, so checks
  /// that question the owner (such as Verify Library's) leave it alone.
  /// Nothing about the release changes.
  Future<void> confirmOwner({required String albumId, DateTime? now}) {
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final album = await context.albumRepository.getById(albumId.trim());
      if (album == null) {
        throw StateError('Album not found: $albumId');
      }
      final metadataRepository = context.metadataFieldStateRepository;
      if (metadataRepository == null) return;
      await MetadataFieldStateService(repository: metadataRepository).recordAll(
        entityType: MetadataEntityType.album,
        entityId: album.id,
        fieldNames: const [MetadataFields.albumArtist],
        authority: MetadataAuthority.confirmed,
        source: MetadataProvenanceSource.user,
        updatedAt: timestamp,
      );
    });
  }

  Future<AlbumProfileEditResult> updateProfile({
    required String? userId,
    required String albumId,
    required String primaryEditionId,
    required String title,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    ReleaseDatePrecision? releaseDatePrecision,
    String? artistId,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedAlbumId = albumId.trim();
    final normalizedEditionId = primaryEditionId.trim();
    final normalizedArtistId = artistId?.trim();

    final trimmedTitle = title.trim();
    final trimmedEditionTitle = editionTitle.trim();
    final trimmedGenre = genre?.trim();

    final normalizedGenre = trimmedGenre == null || trimmedGenre.isEmpty
        ? null
        : trimmedGenre;

    if (normalizedAlbumId.isEmpty) {
      throw ArgumentError.value(
        albumId,
        'albumId',
        'Album id must not be blank.',
      );
    }

    if (normalizedEditionId.isEmpty) {
      throw ArgumentError.value(
        primaryEditionId,
        'primaryEditionId',
        'Primary edition id must not be blank.',
      );
    }

    if (artistId != null && normalizedArtistId!.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Album title must not be blank.',
      );
    }

    if (trimmedEditionTitle.isEmpty) {
      throw ArgumentError.value(
        editionTitle,
        'editionTitle',
        'Edition title must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final album = await context.albumRepository.getById(normalizedAlbumId);

      if (album == null) {
        throw StateError('Album not found: $normalizedAlbumId');
      }

      final targetArtistId = normalizedArtistId ?? album.artistId;

      final artist = await context.artistRepository.getById(targetArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $targetArtistId');
      }

      final edition = await context.albumEditionRepository.getById(
        normalizedEditionId,
      );

      if (edition == null) {
        throw StateError('Album edition not found: $normalizedEditionId');
      }

      if (edition.albumId != album.id) {
        throw StateError(
          'Album edition $normalizedEditionId does not belong to '
          'album $normalizedAlbumId',
        );
      }

      if (!edition.isPrimary) {
        throw StateError(
          'Album edition $normalizedEditionId is not the primary edition.',
        );
      }

      final canonicalTitle = TextNormalizer.canonicalize(trimmedTitle);

      // A caller that does not state the precision keeps an unchanged
      // date's precision; a newly entered full date is an exact day.
      final precision = releaseDate == null
          ? null
          : releaseDatePrecision ??
                (releaseDate == edition.releaseDate
                    ? edition.releaseDatePrecision
                    : ReleaseDatePrecision.day);
      final releaseDateChanged =
          edition.releaseDate != releaseDate ||
          edition.releaseDatePrecision != precision;

      final changedAlbumMetadataFields = <String>{
        if (album.artistId != targetArtistId) MetadataFields.albumArtist,
        if (album.title != trimmedTitle) MetadataFields.albumTitle,
      };

      final changedEditionMetadataFields = <String>{
        if (edition.title != trimmedEditionTitle) MetadataFields.editionTitle,
        if (edition.type != editionType) MetadataFields.editionType,
        if (releaseDateChanged) MetadataFields.editionReleaseDate,
        if (edition.genre != normalizedGenre) MetadataFields.editionGenre,
      };

      final albumChanged =
          album.artistId != targetArtistId ||
          album.title != trimmedTitle ||
          album.canonicalTitle != canonicalTitle;

      final editionChanged =
          edition.title != trimmedEditionTitle ||
          edition.type != editionType ||
          releaseDateChanged ||
          edition.genre != normalizedGenre;

      final updatedAlbum = albumChanged
          ? album.copyWith(
              artistId: targetArtistId,
              title: trimmedTitle,
              canonicalTitle: canonicalTitle,
              updatedAt: timestamp,
            )
          : album;

      final updatedEdition = editionChanged
          ? edition.copyWith(
              title: trimmedEditionTitle,
              type: editionType,
              releaseDate: releaseDate,
              releaseDatePrecision: precision,
              genre: normalizedGenre,
              updatedAt: timestamp,
            )
          : edition;

      if (albumChanged) {
        await context.albumRepository.save(updatedAlbum);

        final metadataRepository = context.metadataFieldStateRepository;

        if (metadataRepository != null &&
            changedAlbumMetadataFields.isNotEmpty) {
          await MetadataFieldStateService(
            repository: metadataRepository,
          ).recordAll(
            entityType: MetadataEntityType.album,
            entityId: updatedAlbum.id,
            fieldNames: changedAlbumMetadataFields,
            authority: MetadataAuthority.manual,
            source: MetadataProvenanceSource.user,
            updatedAt: timestamp,
          );
        }

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.album,
          entityId: updatedAlbum.id,
        );
      }

      if (editionChanged) {
        await context.albumEditionRepository.save(updatedEdition);

        final metadataRepository = context.metadataFieldStateRepository;

        if (metadataRepository != null &&
            changedEditionMetadataFields.isNotEmpty) {
          await MetadataFieldStateService(
            repository: metadataRepository,
          ).recordAll(
            entityType: MetadataEntityType.albumEdition,
            entityId: updatedEdition.id,
            fieldNames: changedEditionMetadataFields,
            authority: MetadataAuthority.manual,
            source: MetadataProvenanceSource.user,
            updatedAt: timestamp,
          );
        }

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.albumEdition,
          entityId: updatedEdition.id,
        );
      }

      return AlbumProfileEditResult(
        album: updatedAlbum,
        primaryEdition: updatedEdition,
        albumChanged: albumChanged,
        primaryEditionChanged: editionChanged,
      );
    });
  }
}
