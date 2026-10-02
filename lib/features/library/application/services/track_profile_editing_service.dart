import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/song_artist_credit.dart';
import 'song_artist_credit_service.dart';

class TrackProfileEditResult {
  const TrackProfileEditResult({required this.song, required this.changed});

  final Song song;
  final bool changed;
}

class TrackProfileEditingService {
  const TrackProfileEditingService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<TrackProfileEditResult> updateTrack({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedSongId = songId.trim();
    final trimmedTitle = title.trim();
    final normalizedFeaturedArtists = _normalizeFeaturedArtists(
      featuredArtists,
    );

    final normalizedArtistId = artistId?.trim();
    final normalizedAlbumId = albumId?.trim();
    final normalizedAlbumEditionId = albumEditionId?.trim();

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

    if (discNumber < 0) {
      throw ArgumentError.value(
        discNumber,
        'discNumber',
        'Disc number must not be negative.',
      );
    }

    if (artistId != null && normalizedArtistId!.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    if (albumId != null && normalizedAlbumId!.isEmpty) {
      throw ArgumentError.value(
        albumId,
        'albumId',
        'Album id must not be blank.',
      );
    }

    if (albumEditionId != null && normalizedAlbumEditionId!.isEmpty) {
      throw ArgumentError.value(
        albumEditionId,
        'albumEditionId',
        'Album edition id must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final targetArtistId = normalizedArtistId ?? song.artistId;
      final targetAlbumId = normalizedAlbumId ?? song.albumId;
      final targetEditionId = normalizedAlbumEditionId ?? song.albumEditionId;

      final targetArtist = await context.artistRepository.getById(
        targetArtistId,
      );

      if (targetArtist == null) {
        throw StateError('Artist not found: $targetArtistId');
      }

      final targetAlbum = await context.albumRepository.getById(targetAlbumId);

      if (targetAlbum == null) {
        throw StateError('Album not found: $targetAlbumId');
      }

      final targetEdition = await context.albumEditionRepository.getById(
        targetEditionId,
      );

      if (targetEdition == null) {
        throw StateError('Album edition not found: $targetEditionId');
      }

      if (targetEdition.albumId != targetAlbum.id) {
        throw StateError(
          'Album edition $targetEditionId does not belong to '
          'album $targetAlbumId',
        );
      }

      final canonicalTitle = TextNormalizer.canonicalize(trimmedTitle);

      final changed =
          song.artistId != targetArtistId ||
          song.albumId != targetAlbumId ||
          song.albumEditionId != targetEditionId ||
          song.title != trimmedTitle ||
          song.canonicalTitle != canonicalTitle ||
          song.trackNumber != trackNumber ||
          song.discNumber != discNumber ||
          song.isSingle != isSingle ||
          !_listsEqual(song.featuredArtists, normalizedFeaturedArtists);

      if (!changed) {
        return TrackProfileEditResult(song: song, changed: false);
      }

      final updated = song.copyWith(
        artistId: targetArtistId,
        albumId: targetAlbumId,
        albumEditionId: targetEditionId,
        title: trimmedTitle,
        canonicalTitle: canonicalTitle,
        trackNumber: trackNumber,
        discNumber: discNumber,
        isSingle: isSingle,
        featuredArtists: List<String>.unmodifiable(normalizedFeaturedArtists),
        updatedAt: timestamp,
      );
      final structuredCredits =
          await SongArtistCreditService.replaceCreditsInContext(
            context: context,
            userId: normalizedUserId,
            songId: updated.id,
            primaryArtistId: targetArtistId,
            additionalCredits: [
              for (final featuredArtist in normalizedFeaturedArtists)
                SongArtistCreditInput(
                  creditedName: featuredArtist,
                  role: SongArtistCreditRole.featured,
                ),
            ],
            now: timestamp,
          );

      final authoritativeFeaturedArtists = [
        for (final credit in structuredCredits)
          if (credit.role == SongArtistCreditRole.featured) credit.creditedName,
      ];

      final persisted = updated.copyWith(
        featuredArtists: List<String>.unmodifiable(
          authoritativeFeaturedArtists,
        ),
      );

      await context.songRepository.save(persisted);

      await context.localSyncRepository.recordUpsert(
        userId: normalizedUserId,
        entityType: CloudDataEntity.song,
        entityId: persisted.id,
      );

      return TrackProfileEditResult(song: persisted, changed: true);
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
