import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/artist.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/metadata/metadata_fields.dart';
import '../../domain/services/metadata_field_state_service.dart';

class ArtistStillReferencedException implements Exception {
  const ArtistStillReferencedException();
}

class ArtistNameCollisionException implements Exception {
  const ArtistNameCollisionException({
    required this.artistId,
    required this.conflictingArtistId,
    required this.name,
  });

  final String artistId;
  final String conflictingArtistId;
  final String name;

  @override
  String toString() {
    return 'ArtistNameCollisionException('
        'artistId: $artistId, '
        'conflictingArtistId: $conflictingArtistId, '
        'name: $name)';
  }
}

class ArtistProfileEditingService {
  const ArtistProfileEditingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<void> removeArtist({
    required String? userId,
    required String artistId,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedArtistId = artistId.trim();

    if (normalizedArtistId.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      final albums = await context.albumRepository.getByArtistId(
        normalizedArtistId,
      );
      final songs = await context.songRepository.getByArtistId(
        normalizedArtistId,
      );
      final credits = await context.songArtistCreditRepository.getByArtistId(
        normalizedArtistId,
      );

      if (albums.isNotEmpty || songs.isNotEmpty || credits.isNotEmpty) {
        throw const ArtistStillReferencedException();
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await metadataRepository.deleteByEntity(
          entityType: MetadataEntityType.artist,
          entityId: normalizedArtistId,
        );
      }

      await context.artistRepository.delete(normalizedArtistId);

      await context.localSyncRepository.recordDelete(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: normalizedArtistId,
      );
    });
  }

  Future<Artist> renameArtist({
    required String? userId,
    required String artistId,
    required String name,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedArtistId = artistId.trim();
    final trimmedName = name.trim();

    if (normalizedArtistId.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Artist name must not be blank.');
    }

    final canonicalName = TextNormalizer.canonicalize(trimmedName);
    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      if (artist.name == trimmedName) {
        return artist;
      }

      final conflictingArtists = (await context.artistRepository.getAll())
          .where(
            (candidate) =>
                candidate.id != normalizedArtistId &&
                candidate.canonicalName == canonicalName,
          )
          .toList(growable: false);

      if (conflictingArtists.isNotEmpty) {
        throw ArtistNameCollisionException(
          artistId: normalizedArtistId,
          conflictingArtistId: conflictingArtists.first.id,
          name: trimmedName,
        );
      }

      final updated = artist.copyWith(
        name: trimmedName,
        canonicalName: canonicalName,
        updatedAt: timestamp,
      );

      await context.artistRepository.save(updated);

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await MetadataFieldStateService(
          repository: metadataRepository,
        ).recordAll(
          entityType: MetadataEntityType.artist,
          entityId: updated.id,
          fieldNames: const {MetadataFields.artistName},
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: updated.id,
      );

      return updated;
    });
  }
}
