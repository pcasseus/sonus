import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/artist.dart';

class ArtistStillReferencedException implements Exception {
  const ArtistStillReferencedException();
}

class ArtistProfileEditingService {
  const ArtistProfileEditingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<void> removeArtist({
    required String userId,
    required String artistId,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedArtistId = artistId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

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

      if (albums.isNotEmpty || songs.isNotEmpty) {
        throw const ArtistStillReferencedException();
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
    required String userId,
    required String artistId,
    required String name,
    DateTime? now,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedArtistId = artistId.trim();
    final trimmedName = name.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

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

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artist = await context.artistRepository.getById(normalizedArtistId);

      if (artist == null) {
        throw StateError('Artist not found: $normalizedArtistId');
      }

      final updated = artist.copyWith(
        name: trimmedName,
        canonicalName: TextNormalizer.canonicalize(trimmedName),
        updatedAt: timestamp,
      );

      await context.artistRepository.save(updated);

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: updated.id,
      );

      return updated;
    });
  }
}
