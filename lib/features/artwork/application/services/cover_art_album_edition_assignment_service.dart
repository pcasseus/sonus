import '../../../../core/identity/text_normalizer.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/metadata/metadata_fields.dart';
import '../../../library/domain/services/metadata_authority_policy.dart';
import '../../../library/domain/services/metadata_field_state_service.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/artwork_asset_factory.dart';
import 'album_edition_artwork_authority.dart';

class CoverArtAlbumEditionAssignmentResult {
  const CoverArtAlbumEditionAssignmentResult({
    required this.decision,
    this.artworkId,
    this.changed = false,
  });

  final MetadataReplacementDecision decision;
  final String? artworkId;
  final bool changed;

  bool get applied => decision == MetadataReplacementDecision.accept;
}

class CoverArtAlbumEditionAssignmentService {
  const CoverArtAlbumEditionAssignmentService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  /// Reads current artwork authority before downloading a CAA image.
  ///
  /// This is an optimization, not authorization to assign artwork.
  /// assignManagedArtwork must recheck authority inside its transaction.
  Future<CoverArtAlbumEditionAssignmentResult> evaluateBeforeDownload({
    required String albumEditionId,
  }) {
    final id = albumEditionId.trim();

    if (id.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition ID is required.',
      );
    }

    return mutationRunner.run((context) async {
      final edition = await context.albumEditionRepository.getById(id);

      if (edition == null) {
        throw StateError('Album edition not found: $id');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Metadata field state repository is required.');
      }

      final existingState = await metadataRepository.get(
        entityType: MetadataEntityType.albumEdition,
        entityId: id,
        fieldName: MetadataFields.editionArtwork,
      );

      final decision = AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: edition.artworkId,
        currentState: existingState,
      );

      return CoverArtAlbumEditionAssignmentResult(
        decision: decision,
        artworkId: edition.artworkId,
      );
    });
  }

  Future<CoverArtAlbumEditionAssignmentResult> assignManagedArtwork({
    required String albumEditionId,
    required String managedFilePath,
    required String sourceReference,
    String? userId,
    DateTime? now,
  }) {
    final id = albumEditionId.trim();
    final filePath = managedFilePath.trim();
    final reference = sourceReference.trim();

    if (id.isEmpty || filePath.isEmpty || reference.isEmpty) {
      throw ArgumentError('Edition ID, artwork path, and source are required.');
    }

    if (!reference.startsWith('coverartarchive:')) {
      throw ArgumentError.value(
        sourceReference,
        'sourceReference',
        'Expected Cover Art Archive provenance.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final edition = await context.albumEditionRepository.getById(id);

      if (edition == null) {
        throw StateError('Album edition not found: $id');
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Metadata field state repository is required.');
      }

      final existingState = await metadataRepository.get(
        entityType: MetadataEntityType.albumEdition,
        entityId: id,
        fieldName: MetadataFields.editionArtwork,
      );

      final decision = AlbumEditionArtworkAuthority.evaluateAutomatic(
        currentArtworkId: edition.artworkId,
        currentState: existingState,
      );

      if (decision != MetadataReplacementDecision.accept) {
        return CoverArtAlbumEditionAssignmentResult(
          decision: decision,
          artworkId: edition.artworkId,
        );
      }

      final normalizedPath = TextNormalizer.normalizePath(filePath);

      var artwork = await context.artworkAssetRepository.getByNormalizedPath(
        normalizedPath,
      );

      final created = artwork == null;

      if (artwork == null) {
        artwork = ArtworkAssetFactory.create(
          filePath: filePath,
          now: timestamp,
        );

        await context.artworkAssetRepository.create(artwork);
      }

      final changed = edition.artworkId != artwork.id;

      if (changed) {
        await context.albumEditionRepository.save(
          edition.copyWith(artworkId: artwork.id, updatedAt: timestamp),
        );
      }

      final provenanceChanged =
          existingState == null ||
          existingState.authority != MetadataAuthority.external ||
          existingState.source != MetadataProvenanceSource.coverArtArchive ||
          existingState.sourceReference != reference;

      if (changed || provenanceChanged) {
        final recorded =
            await MetadataFieldStateService(
              repository: metadataRepository,
            ).record(
              entityType: MetadataEntityType.albumEdition,
              entityId: id,
              fieldName: MetadataFields.editionArtwork,
              authority: MetadataAuthority.external,
              source: MetadataProvenanceSource.coverArtArchive,
              sourceReference: reference,
              updatedAt: timestamp,
            );

        if (!recorded) {
          throw StateError('Artwork provenance update was rejected.');
        }
      }

      if (created) {
        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.artworkAsset,
          entityId: artwork.id,
        );
      }

      if (changed || provenanceChanged) {
        await context.localSyncRepository.recordUpsert(
          userId: userId?.trim(),
          entityType: CloudDataEntity.albumEdition,
          entityId: id,
        );
      }

      return CoverArtAlbumEditionAssignmentResult(
        decision: decision,
        artworkId: artwork.id,
        changed: changed,
      );
    });
  }
}
