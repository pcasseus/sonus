import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/song.dart';

class SongBlockService {
  const SongBlockService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<Song> setBlocked({
    required String userId,
    required String songId,
    required bool isBlocked,
    DateTime? now,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedSongId = songId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final updated = song.copyWith(isBlocked: isBlocked, updatedAt: timestamp);

      await context.songRepository.save(updated);

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.song,
        entityId: updated.id,
      );

      return updated;
    });
  }
}
