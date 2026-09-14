import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/song.dart';

class TrackProfileEditResult {
  const TrackProfileEditResult({required this.song, required this.changed});

  final Song song;
  final bool changed;
}

class TrackProfileEditingService {
  const TrackProfileEditingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<TrackProfileEditResult> updateTrack({
    required String userId,
    required String songId,
    required String title,
    required int trackNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    DateTime? now,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedSongId = songId.trim();
    final trimmedTitle = title.trim();
    final normalizedFeaturedArtists = _normalizeFeaturedArtists(
      featuredArtists,
    );

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (normalizedSongId.isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'Song id must not be blank.');
    }

    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Song title must not be blank.',
      );
    }

    if (trackNumber < 0) {
      throw ArgumentError.value(
        trackNumber,
        'trackNumber',
        'Track number must not be negative.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final canonicalTitle = TextNormalizer.canonicalize(trimmedTitle);

      final changed =
          song.title != trimmedTitle ||
          song.canonicalTitle != canonicalTitle ||
          song.trackNumber != trackNumber ||
          song.isSingle != isSingle ||
          !_listsEqual(song.featuredArtists, normalizedFeaturedArtists);

      if (!changed) {
        return TrackProfileEditResult(song: song, changed: false);
      }

      final updated = song.copyWith(
        title: trimmedTitle,
        canonicalTitle: canonicalTitle,
        trackNumber: trackNumber,
        isSingle: isSingle,
        featuredArtists: List<String>.unmodifiable(normalizedFeaturedArtists),
        updatedAt: timestamp,
      );

      await context.songRepository.save(updated);

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.song,
        entityId: updated.id,
      );

      return TrackProfileEditResult(song: updated, changed: true);
    });
  }

  List<String> _normalizeFeaturedArtists(List<String> artists) {
    return [
      for (final artist in artists)
        if (artist.trim().isNotEmpty) artist.trim(),
    ];
  }

  bool _listsEqual(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }
}
