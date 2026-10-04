import '../../../../core/identity/artist_credit_parser.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import 'song_artist_credit_service.dart';

enum ArtistIdentityRepairStatus {
  repaired,
  sourceMissing,
  notMalformed,
  targetArtistMalformed,
  primaryArtistMissing,
  primaryArtistAmbiguous,
  albumCollision,
}

class ArtistIdentityRepairResult {
  const ArtistIdentityRepairResult({
    required this.status,
    this.sourceArtistId,
    this.targetArtistId,
    this.repairedSongCount = 0,
    this.repairedAlbumCount = 0,
  });

  final ArtistIdentityRepairStatus status;
  final String? sourceArtistId;
  final String? targetArtistId;
  final int repairedSongCount;
  final int repairedAlbumCount;

  bool get repaired => status == ArtistIdentityRepairStatus.repaired;
}

class MalformedArtistIdentityRepairService {
  const MalformedArtistIdentityRepairService({
    required this.mutationRunner,
    this.artistCreditParser = const ArtistCreditParser(),
  });

  final SyncMutationRunner mutationRunner;
  final ArtistCreditParser artistCreditParser;

  Future<ArtistIdentityRepairResult> repairArtist({
    required String? userId,
    required String artistId,
    DateTime? now,
  }) {
    final normalizedArtistId = artistId.trim();
    final normalizedUserId = userId?.trim();

    if (normalizedArtistId.isEmpty) {
      throw ArgumentError.value(
        artistId,
        'artistId',
        'Artist id must not be blank.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return mutationRunner.run((context) async {
      final sourceArtist = await context.artistRepository.getById(
        normalizedArtistId,
      );

      if (sourceArtist == null) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.sourceMissing,
          sourceArtistId: normalizedArtistId,
        );
      }

      final parsed = artistCreditParser.parseExplicitFeatureCredit(
        sourceArtist.name,
      );

      if (parsed == null) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.notMalformed,
          sourceArtistId: sourceArtist.id,
        );
      }

      final primaryCanonicalName = TextNormalizer.canonicalize(
        parsed.primaryArtist,
      );

      if (primaryCanonicalName.isEmpty) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.notMalformed,
          sourceArtistId: sourceArtist.id,
        );
      }

      final primaryMatches = (await context.artistRepository.getAll())
          .where(
            (artist) =>
                artist.id != sourceArtist.id &&
                artist.canonicalName == primaryCanonicalName,
          )
          .toList(growable: false);

      if (primaryMatches.isEmpty) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.primaryArtistMissing,
          sourceArtistId: sourceArtist.id,
        );
      }

      if (primaryMatches.length != 1) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.primaryArtistAmbiguous,
          sourceArtistId: sourceArtist.id,
        );
      }

      final targetArtist = primaryMatches.single;

      if (artistCreditParser.parseExplicitFeatureCredit(targetArtist.name) !=
          null) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.targetArtistMalformed,
          sourceArtistId: sourceArtist.id,
          targetArtistId: targetArtist.id,
        );
      }

      final sourceAlbums = await context.albumRepository.getByArtistId(
        sourceArtist.id,
      );

      final targetAlbums = await context.albumRepository.getByArtistId(
        targetArtist.id,
      );

      final targetAlbumCanonicalTitles = targetAlbums
          .map((album) => album.canonicalTitle)
          .toSet();

      final hasAlbumCollision = sourceAlbums.any(
        (album) => targetAlbumCanonicalTitles.contains(album.canonicalTitle),
      );

      if (hasAlbumCollision) {
        return ArtistIdentityRepairResult(
          status: ArtistIdentityRepairStatus.albumCollision,
          sourceArtistId: sourceArtist.id,
          targetArtistId: targetArtist.id,
        );
      }

      final sourceSongs = await context.songRepository.getByArtistId(
        sourceArtist.id,
      );

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
              artistId: credit.artistId,
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

        final parsedFeatureCanonicalName = TextNormalizer.canonicalize(
          parsed.featuredArtist,
        );

        final alreadyContainsParsedFeature = additionalCredits.any(
          (credit) =>
              TextNormalizer.canonicalize(credit.creditedName) ==
              parsedFeatureCanonicalName,
        );

        if (!alreadyContainsParsedFeature &&
            parsedFeatureCanonicalName.isNotEmpty &&
            parsedFeatureCanonicalName != targetArtist.canonicalName) {
          additionalCredits.add(
            SongArtistCreditInput(
              creditedName: parsed.featuredArtist,
              role: SongArtistCreditRole.featured,
            ),
          );
        }

        final credits =
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
          for (final credit in credits)
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
          'Malformed artist still has references after repair: '
          '${sourceArtist.id}',
        );
      }

      await context.artistRepository.delete(sourceArtist.id);

      await context.localSyncRepository.recordDelete(
        userId: normalizedUserId,
        entityType: CloudDataEntity.artist,
        entityId: sourceArtist.id,
      );

      return ArtistIdentityRepairResult(
        status: ArtistIdentityRepairStatus.repaired,
        sourceArtistId: sourceArtist.id,
        targetArtistId: targetArtist.id,
        repairedSongCount: sourceSongs.length,
        repairedAlbumCount: sourceAlbums.length,
      );
    });
  }
}
