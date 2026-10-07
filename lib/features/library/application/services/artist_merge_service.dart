import '../../../../core/identity/text_normalizer.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../domain/metadata/metadata_field_state.dart';
import 'song_artist_credit_service.dart';

class ArtistMergeSameIdentityException implements Exception {
  const ArtistMergeSameIdentityException();
}

class ArtistMergeAlbumCollisionException implements Exception {
  const ArtistMergeAlbumCollisionException({
    required this.sourceArtistId,
    required this.targetArtistId,
    required this.canonicalAlbumTitle,
  });

  final String sourceArtistId;
  final String targetArtistId;
  final String canonicalAlbumTitle;
}

class ArtistMergeCreditCollisionException implements Exception {
  const ArtistMergeCreditCollisionException({
    required this.songId,
    required this.sourceArtistId,
    required this.targetArtistId,
  });

  final String songId;
  final String sourceArtistId;
  final String targetArtistId;
}

class ArtistMergeResult {
  const ArtistMergeResult({
    required this.sourceArtistId,
    required this.targetArtistId,
    required this.movedAlbumCount,
    required this.movedPrimarySongCount,
    required this.relinkedCreditCount,
    required this.linkedUnlinkedCreditCount,
  });

  final String sourceArtistId;
  final String targetArtistId;
  final int movedAlbumCount;
  final int movedPrimarySongCount;
  final int relinkedCreditCount;
  final int linkedUnlinkedCreditCount;
}

class ArtistMergeService {
  const ArtistMergeService({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<ArtistMergeResult> mergeArtists({
    required String? userId,
    required String sourceArtistId,
    required String targetArtistId,
    DateTime? now,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedSourceArtistId = sourceArtistId.trim();
    final normalizedTargetArtistId = targetArtistId.trim();

    if (normalizedSourceArtistId.isEmpty) {
      throw ArgumentError.value(
        sourceArtistId,
        'sourceArtistId',
        'Source artist id must not be blank.',
      );
    }

    if (normalizedTargetArtistId.isEmpty) {
      throw ArgumentError.value(
        targetArtistId,
        'targetArtistId',
        'Target artist id must not be blank.',
      );
    }

    if (normalizedSourceArtistId == normalizedTargetArtistId) {
      throw const ArtistMergeSameIdentityException();
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final sourceArtist = await context.artistRepository.getById(
        normalizedSourceArtistId,
      );
      final targetArtist = await context.artistRepository.getById(
        normalizedTargetArtistId,
      );

      if (sourceArtist == null) {
        throw StateError('Source artist not found: $normalizedSourceArtistId');
      }

      if (targetArtist == null) {
        throw StateError('Target artist not found: $normalizedTargetArtistId');
      }

      final sourceAlbums = await context.albumRepository.getByArtistId(
        sourceArtist.id,
      );
      final targetAlbums = await context.albumRepository.getByArtistId(
        targetArtist.id,
      );

      final targetAlbumTitles = targetAlbums
          .map((album) => album.canonicalTitle)
          .toSet();

      for (final album in sourceAlbums) {
        if (targetAlbumTitles.contains(album.canonicalTitle)) {
          throw ArtistMergeAlbumCollisionException(
            sourceArtistId: sourceArtist.id,
            targetArtistId: targetArtist.id,
            canonicalAlbumTitle: album.canonicalTitle,
          );
        }
      }

      final sourceSongs = await context.songRepository.getByArtistId(
        sourceArtist.id,
      );
      final sourceSongIds = sourceSongs.map((song) => song.id).toSet();

      final sourceCredits = await context.songArtistCreditRepository
          .getByArtistId(sourceArtist.id);

      final externalSourceCredits = sourceCredits
          .where((credit) => !sourceSongIds.contains(credit.songId))
          .toList(growable: false);

      final externalSongIds = externalSourceCredits
          .map((credit) => credit.songId)
          .toSet();

      for (final songId in externalSongIds) {
        final credits = await context.songArtistCreditRepository.getBySongId(
          songId,
        );

        final alreadyReferencesTarget = credits.any(
          (credit) => credit.artistId == targetArtist.id,
        );

        if (alreadyReferencesTarget) {
          throw ArtistMergeCreditCollisionException(
            songId: songId,
            sourceArtistId: sourceArtist.id,
            targetArtistId: targetArtist.id,
          );
        }
      }

      for (final album in sourceAlbums) {
        final updatedAlbum = album.copyWith(
          artistId: targetArtist.id,
          updatedAt: timestamp,
        );

        await context.albumRepository.save(updatedAlbum);

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.album,
          entityId: updatedAlbum.id,
        );
      }

      for (final song in sourceSongs) {
        final currentCredits = await context.songArtistCreditRepository
            .getBySongId(song.id);

        final additionalCredits = <SongArtistCreditInput>[];

        for (final credit in currentCredits) {
          if (credit.role == SongArtistCreditRole.primary) {
            continue;
          }

          additionalCredits.add(
            SongArtistCreditInput(
              creditedName: credit.creditedName,
              role: credit.role,
              artistId: credit.artistId == sourceArtist.id
                  ? targetArtist.id
                  : credit.artistId,
            ),
          );
        }

        final existingCanonicalCredits = additionalCredits
            .map((credit) => TextNormalizer.canonicalize(credit.creditedName))
            .where((canonicalName) => canonicalName.isNotEmpty)
            .toSet();

        for (final legacyFeaturedArtist in song.featuredArtists) {
          final canonicalName = TextNormalizer.canonicalize(
            legacyFeaturedArtist,
          );

          if (canonicalName.isEmpty ||
              canonicalName == targetArtist.canonicalName ||
              existingCanonicalCredits.contains(canonicalName)) {
            continue;
          }

          additionalCredits.add(
            SongArtistCreditInput(
              creditedName: legacyFeaturedArtist,
              role: SongArtistCreditRole.featured,
            ),
          );

          existingCanonicalCredits.add(canonicalName);
        }

        final rebuiltCredits =
            await SongArtistCreditService.replaceCreditsWithRepositories(
              artistRepository: context.artistRepository,
              songRepository: context.songRepository,
              songArtistCreditRepository: context.songArtistCreditRepository,
              songId: song.id,
              primaryArtistId: targetArtist.id,
              additionalCredits: additionalCredits,
              onArtistCreated: (createdArtistId) {
                return context.localSyncRepository.recordUpsert(
                  userId: normalizedUserId,
                  entityType: CloudDataEntity.artist,
                  entityId: createdArtistId,
                );
              },
              now: timestamp,
            );

        final featuredArtists = [
          for (final credit in rebuiltCredits)
            if (credit.role == SongArtistCreditRole.featured)
              credit.creditedName,
        ];

        final updatedSong = song.copyWith(
          artistId: targetArtist.id,
          featuredArtists: List<String>.unmodifiable(featuredArtists),
          updatedAt: timestamp,
        );

        await context.songRepository.save(updatedSong);

        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.song,
          entityId: updatedSong.id,
        );
      }

      var relinkedCreditCount = 0;

      for (final credit in externalSourceCredits) {
        await context.songArtistCreditRepository.save(
          credit.copyWith(artistId: targetArtist.id, updatedAt: timestamp),
        );

        relinkedCreditCount++;
      }

      for (final songId in externalSongIds) {
        await context.localSyncRepository.recordUpsert(
          userId: normalizedUserId,
          entityType: CloudDataEntity.song,
          entityId: songId,
        );
      }

      final identityRepairRepository = context.artistIdentityRepairRepository;

      if (identityRepairRepository == null) {
        throw StateError('Artist identity repair repository is unavailable.');
      }

      await identityRepairRepository.remapHistoricalArtistReferences(
        sourceArtistId: sourceArtist.id,
        targetArtistId: targetArtist.id,
        targetArtistName: targetArtist.name,
      );

      final remainingAlbums = await context.albumRepository.getByArtistId(
        sourceArtist.id,
      );
      final remainingSongs = await context.songRepository.getByArtistId(
        sourceArtist.id,
      );
      final remainingCredits = await context.songArtistCreditRepository
          .getByArtistId(sourceArtist.id);

      if (remainingAlbums.isNotEmpty ||
          remainingSongs.isNotEmpty ||
          remainingCredits.isNotEmpty) {
        throw StateError(
          'Source artist still has references after merge: '
          '${sourceArtist.id}',
        );
      }

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await metadataRepository.deleteByEntity(
          entityType: MetadataEntityType.artist,
          entityId: sourceArtist.id,
        );
      }

      await context.artistRepository.delete(sourceArtist.id);

      await context.localSyncRepository.recordDelete(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: sourceArtist.id,
      );

      var linkedUnlinkedCreditCount = 0;

      final remainingCanonicalMatches =
          (await context.artistRepository.getAll())
              .where(
                (artist) => artist.canonicalName == targetArtist.canonicalName,
              )
              .toList(growable: false);

      if (remainingCanonicalMatches.length == 1 &&
          remainingCanonicalMatches.single.id == targetArtist.id) {
        final unlinkedCredits = await context.songArtistCreditRepository
            .getUnlinkedByCanonicalName(targetArtist.canonicalName);

        final affectedSongIds = <String>{};

        for (final credit in unlinkedCredits) {
          await context.songArtistCreditRepository.save(
            credit.copyWith(artistId: targetArtist.id, updatedAt: timestamp),
          );

          affectedSongIds.add(credit.songId);
          linkedUnlinkedCreditCount++;
        }

        for (final songId in affectedSongIds) {
          await context.localSyncRepository.recordUpsert(
            userId: normalizedUserId,
            entityType: CloudDataEntity.song,
            entityId: songId,
          );
        }
      }

      return ArtistMergeResult(
        sourceArtistId: sourceArtist.id,
        targetArtistId: targetArtist.id,
        movedAlbumCount: sourceAlbums.length,
        movedPrimarySongCount: sourceSongs.length,
        relinkedCreditCount: relinkedCreditCount,
        linkedUnlinkedCreditCount: linkedUnlinkedCreditCount,
      );
    });
  }
}
