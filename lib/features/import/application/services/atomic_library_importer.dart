import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/identity/import_identity_metadata_normalizer.dart';
import 'package:sonus_next/features/import/application/identity/library_identity_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/daos/song_import_review_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_song_import_review_repository.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_artist_credit_repository.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_local_sync_repository.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

typedef BeforeBindingWrite = Future<void> Function();

class AtomicLibraryImporter {
  const AtomicLibraryImporter({
    required this.appDatabase,
    this.userId,
    this.beforeBindingWrite,
  });

  final AppDatabase appDatabase;
  final String? userId;
  final BeforeBindingWrite? beforeBindingWrite;

  Future<ImportResult> import({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
    MetadataSource metadataSource = MetadataSource.embedded,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final syncUserId = userId?.trim();

    try {
      return await appDatabase.transaction((transaction) async {
        final artistRepository = SqliteArtistRepository(ArtistDao(transaction));
        final albumRepository = SqliteAlbumRepository(AlbumDao(transaction));
        final editionRepository = SqliteAlbumEditionRepository(
          AlbumEditionDao(transaction),
        );
        final songRepository = SqliteSongRepository(SongDao(transaction));
        final songArtistCreditRepository = SqliteSongArtistCreditRepository(
          SongArtistCreditDao(transaction),
        );
        final bindingRepository = SqliteMediaFileBindingRepository(
          MediaFileBindingDao(transaction),
        );
        final reviewRepository = SqliteSongImportReviewRepository(
          SongImportReviewDao(transaction),
        );
        final localSyncRepository = SqliteLocalSyncRepository(
          dao: LocalSyncDao(transaction),
          generateId: EntityId.syncOutbox,
          now: () => timestamp,
        );

        final normalizedPath = TextNormalizer.normalizePath(candidate.filePath);

        final existingPathBinding = await bindingRepository.getByNormalizedPath(
          normalizedPath,
        );

        if (existingPathBinding != null) {
          if (existingPathBinding.isAvailable) {
            return ImportResult(
              status: ImportResultStatus.skipped,
              filePath: candidate.filePath,
              songId: existingPathBinding.songId,
            );
          }

          final reactivatedBinding = existingPathBinding.copyWith(
            filePath: candidate.filePath.trim(),
            normalizedPath: normalizedPath,
            isAvailable: true,
            lastSeenAt: timestamp,
            updatedAt: timestamp,
          );

          await beforeBindingWrite?.call();
          await bindingRepository.save(reactivatedBinding);

          return ImportResult(
            status: ImportResultStatus.relinked,
            filePath: candidate.filePath,
            songId: existingPathBinding.songId,
          );
        }

        final resolver = LibraryIdentityResolver(
          artistRepository: artistRepository,
          albumRepository: albumRepository,
          albumEditionRepository: editionRepository,
          songRepository: songRepository,
        );

        const metadataNormalizer = ImportIdentityMetadataNormalizer();

        final ambiguousArtistCredit = metadataNormalizer
            .ambiguousSeparatorArtistCredit(
              candidate: candidate,
              metadata: metadata,
            );

        var effectiveMetadata = metadataNormalizer.normalize(
          candidate: candidate,
          metadata: metadata,
        );

        if (ambiguousArtistCredit != null) {
          final safePrimaryArtist = effectiveMetadata.effectiveAlbumArtistName
              .trim();

          if (safePrimaryArtist.isNotEmpty) {
            effectiveMetadata = effectiveMetadata.copyWith(
              artistName: safePrimaryArtist,
            );
          }
        }

        final match = await resolver.resolve(effectiveMetadata);

        if (match.hasAmbiguity) {
          return ImportResult(
            status: ImportResultStatus.failed,
            filePath: candidate.filePath,
            failure: const ImportFailure(
              type: ImportFailureType.invalidMetadata,
              message:
                  'Import metadata matches multiple existing library entities.',
            ),
          );
        }

        var artist = match.artist;

        if (artist == null) {
          artist = EntityFactory.createArtist(
            name: effectiveMetadata.artistName,
            now: timestamp,
          );

          await artistRepository.create(artist);

          if (syncUserId != null && syncUserId.isNotEmpty) {
            await localSyncRepository.recordUpsert(
              userId: syncUserId,
              entityType: CloudDataEntity.artist,
              entityId: artist.id,
            );
          }
        }

        var albumArtist = match.albumArtist;

        if (albumArtist == null) {
          final canonicalTrackArtist = TextNormalizer.canonicalize(
            effectiveMetadata.artistName,
          );
          final canonicalAlbumArtist = TextNormalizer.canonicalize(
            effectiveMetadata.effectiveAlbumArtistName,
          );

          if (canonicalAlbumArtist == canonicalTrackArtist) {
            albumArtist = artist;
          } else {
            albumArtist = EntityFactory.createArtist(
              name: effectiveMetadata.effectiveAlbumArtistName,
              now: timestamp,
            );

            await artistRepository.create(albumArtist);

            if (syncUserId != null && syncUserId.isNotEmpty) {
              await localSyncRepository.recordUpsert(
                userId: syncUserId,
                entityType: CloudDataEntity.artist,
                entityId: albumArtist.id,
              );
            }
          }
        }

        var album = match.album;

        if (album == null) {
          album = EntityFactory.createAlbum(
            artistId: albumArtist.id,
            title: metadata.albumTitle,
            now: timestamp,
          );

          await albumRepository.create(album);

          if (syncUserId != null && syncUserId.isNotEmpty) {
            await localSyncRepository.recordUpsert(
              userId: syncUserId,
              entityType: CloudDataEntity.album,
              entityId: album.id,
            );
          }
        }
        var edition = match.edition;

        if (edition == null) {
          edition = EntityFactory.createAlbumEdition(
            albumId: album.id,
            title: effectiveMetadata.albumTitle,
            isPrimary: true,
            releaseDate: metadata.releaseDate,
            genre: metadata.genre,
            now: timestamp,
          );

          await editionRepository.create(edition);

          if (syncUserId != null && syncUserId.isNotEmpty) {
            await localSyncRepository.recordUpsert(
              userId: syncUserId,
              entityType: CloudDataEntity.albumEdition,
              entityId: edition.id,
            );
          }
        }

        var song = match.song;

        if (song == null) {
          song = EntityFactory.createSong(
            artistId: artist.id,
            albumId: album.id,
            albumEditionId: edition.id,
            title: metadata.title,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            durationSeconds: metadata.durationSeconds,
            isSingle: metadata.isSingle,
            featuredArtists: effectiveMetadata.featuredArtists,
            now: timestamp,
          );

          await songRepository.create(song);

          final structuredCredits =
              await SongArtistCreditService.replaceCreditsWithRepositories(
                artistRepository: artistRepository,
                songRepository: songRepository,
                songArtistCreditRepository: songArtistCreditRepository,
                onArtistCreated: syncUserId == null || syncUserId.isEmpty
                    ? null
                    : (artistId) => localSyncRepository.recordUpsert(
                        userId: syncUserId,
                        entityType: CloudDataEntity.artist,
                        entityId: artistId,
                      ),
                songId: song.id,
                primaryArtistId: artist.id,
                additionalCredits: [
                  for (final featuredArtist
                      in effectiveMetadata.featuredArtists)
                    SongArtistCreditInput(
                      creditedName: featuredArtist,
                      role: SongArtistCreditRole.featured,
                    ),
                ],
                now: timestamp,
              );

          final authoritativeFeaturedArtists = [
            for (final credit in structuredCredits)
              if (credit.role == SongArtistCreditRole.featured)
                credit.creditedName,
          ];

          if (!_listsEqual(
            song.featuredArtists,
            authoritativeFeaturedArtists,
          )) {
            song = song.copyWith(
              featuredArtists: List<String>.unmodifiable(
                authoritativeFeaturedArtists,
              ),
              updatedAt: timestamp,
            );

            await songRepository.save(song);
          }

          final reviewReasons = _deriveReviewReasons(
            candidate: candidate,
            metadata: metadata,
            metadataSource: metadataSource,
            ambiguousArtistCredit: ambiguousArtistCredit,
          );

          if (reviewReasons.isNotEmpty) {
            await reviewRepository.create(
              SongImportReview(
                songId: song.id,
                metadataSource: metadataSource,
                reasons: List.unmodifiable(reviewReasons),
                payload: ambiguousArtistCredit == null
                    ? null
                    : ImportReviewPayload(
                        rawArtistCredit: ambiguousArtistCredit,
                      ),
                createdAt: timestamp,
                updatedAt: timestamp,
              ),
            );
          }

          if (syncUserId != null && syncUserId.isNotEmpty) {
            await localSyncRepository.recordUpsert(
              userId: syncUserId,
              entityType: CloudDataEntity.song,
              entityId: song.id,
            );
          }

          final binding = MediaFileBindingFactory.create(
            songId: song.id,
            filePath: candidate.filePath,
            sourceId: candidate.sourceId,
            lastSeenAt: timestamp,
            now: timestamp,
          );

          await beforeBindingWrite?.call();
          await bindingRepository.create(binding);

          return ImportResult(
            status: ImportResultStatus.imported,
            filePath: candidate.filePath,
            songId: song.id,
          );
        }

        final existingSongBindings = await bindingRepository.getBySongId(
          song.id,
        );

        final availableBindings = existingSongBindings
            .where((binding) => binding.isAvailable)
            .toList(growable: false);

        if (availableBindings.isNotEmpty) {
          return ImportResult(
            status: ImportResultStatus.skipped,
            filePath: candidate.filePath,
            songId: song.id,
          );
        }

        final unavailableBindings = existingSongBindings
            .where((binding) => !binding.isAvailable)
            .toList(growable: false);

        if (unavailableBindings.length > 1) {
          return ImportResult(
            status: ImportResultStatus.failed,
            filePath: candidate.filePath,
            songId: song.id,
            failure: const ImportFailure(
              type: ImportFailureType.ambiguousFileBinding,
              message:
                  'Multiple unavailable file bindings exist for this song.',
            ),
          );
        }

        if (unavailableBindings.length == 1) {
          final oldBinding = unavailableBindings.single;

          final relinkedBinding = oldBinding.copyWith(
            filePath: candidate.filePath.trim(),
            normalizedPath: normalizedPath,
            sourceId: candidate.sourceId ?? oldBinding.sourceId,
            isAvailable: true,
            lastSeenAt: timestamp,
            updatedAt: timestamp,
          );

          await beforeBindingWrite?.call();
          await bindingRepository.save(relinkedBinding);

          return ImportResult(
            status: ImportResultStatus.relinked,
            filePath: candidate.filePath,
            songId: song.id,
          );
        }

        final binding = MediaFileBindingFactory.create(
          songId: song.id,
          filePath: candidate.filePath,
          sourceId: candidate.sourceId,
          lastSeenAt: timestamp,
          now: timestamp,
        );

        await beforeBindingWrite?.call();
        await bindingRepository.create(binding);

        return ImportResult(
          status: ImportResultStatus.relinked,
          filePath: candidate.filePath,
          songId: song.id,
        );
      });
    } catch (error) {
      return ImportResult(
        status: ImportResultStatus.failed,
        filePath: candidate.filePath,
        failure: ImportFailure(
          type: ImportFailureType.persistenceFailure,
          message: 'Atomic library import failed: $error',
        ),
      );
    }
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

  List<ImportReviewReason> _deriveReviewReasons({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
    required MetadataSource metadataSource,
    required String? ambiguousArtistCredit,
  }) {
    final reasons = <ImportReviewReason>[];

    if (metadataSource != MetadataSource.embedded) {
      reasons.add(ImportReviewReason.fallbackMetadata);
    }

    if (TextNormalizer.canonicalize(metadata.artistName) == 'unknown artist') {
      reasons.add(ImportReviewReason.unknownArtist);
    }

    if (TextNormalizer.canonicalize(metadata.albumTitle) == 'unknown album') {
      reasons.add(ImportReviewReason.unknownAlbum);
    }

    if (metadata.trackNumber <= 0) {
      reasons.add(ImportReviewReason.missingTrackNumber);
    }

    if (metadata.durationSeconds <= 0) {
      reasons.add(ImportReviewReason.missingDuration);
    }

    if (candidate.structure == ImportCandidateStructure.looseAlbum) {
      reasons.add(ImportReviewReason.looseFolder);
    }

    if (ambiguousArtistCredit != null) {
      reasons.add(ImportReviewReason.ambiguousArtistCredit);
    }

    return reasons;
  }
}
