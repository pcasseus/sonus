import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/artist.dart';

class ArtistCreationService {
  const ArtistCreationService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<Artist> createOrReuse({
    required String userId,
    required String name,
    DateTime? now,
  }) {
    final normalizedUserId = userId.trim();
    final trimmedName = name.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Artist name must not be blank.');
    }

    final canonicalName = TextNormalizer.canonicalize(trimmedName);

    if (canonicalName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Artist name must contain searchable text.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final artists = await context.artistRepository.getAll();

      final matches = artists
          .where((artist) => artist.canonicalName == canonicalName)
          .toList(growable: false);

      if (matches.length > 1) {
        throw StateError(
          'Artist name matches multiple existing artists: $trimmedName',
        );
      }

      if (matches.length == 1) {
        return matches.single;
      }

      final artist = EntityFactory.createArtist(
        name: trimmedName,
        now: timestamp,
      );

      await context.artistRepository.create(artist);

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: artist.id,
      );

      return artist;
    });
  }
}
