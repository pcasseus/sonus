import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/identity/import_identity_metadata_normalizer.dart';
import 'package:sonus_next/features/import/application/identity/library_identity_resolver.dart';
import 'package:sonus_next/features/import/application/metadata/track_title_version_interpreter.dart';
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
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/services/edition_title_parser.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_track_repository.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/services/metadata_field_state_service.dart';
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
    this.relinkOnly = false,
  });

  final AppDatabase appDatabase;
  final String? userId;
  final BeforeBindingWrite? beforeBindingWrite;

  /// Only attach files to songs that already exist (e.g. after restoring a
  /// backup on a new device). Files without an existing song are skipped
  /// and nothing is created or modified for them.
  final bool relinkOnly;

  Future<ImportResult> import({
    required ImportCandidate candidate,
    required AudioMetadata metadata,
    MetadataSource metadataSource = MetadataSource.embedded,
    ImportMetadataOrigins? metadataOrigins,
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
        final albumEditionTrackRepository = SqliteAlbumEditionTrackRepository(
          AlbumEditionTrackDao(transaction),
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

        final metadataFieldStateRepository = SqliteMetadataFieldStateRepository(
          MetadataFieldStateDao(transaction),
        );
        final metadataFieldStateService = MetadataFieldStateService(
          repository: metadataFieldStateRepository,
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
              skipReason: ImportSkipReason.knownFile,
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
        var effectiveOrigins = metadataOrigins;

        if (effectiveOrigins != null) {
          effectiveOrigins = effectiveOrigins.copyWith(
            artistName: effectiveMetadata.artistName != metadata.artistName
                ? ImportMetadataFieldSource.fallback
                : effectiveOrigins.artistName,
            albumArtistName:
                effectiveMetadata.albumArtistName != metadata.albumArtistName
                ? ImportMetadataFieldSource.fallback
                : effectiveOrigins.albumArtistName,
          );
        }

        const titleInterpreter = TrackTitleVersionInterpreter();

        final interpretedTitle = titleInterpreter.interpret(
          effectiveMetadata.title,
        );

        effectiveMetadata = effectiveMetadata.copyWith(
          title: interpretedTitle.title,
        );

        final match = await resolver.resolve(
          effectiveMetadata,
          versionLabel: interpretedTitle.versionLabel,
          versionCharacteristics: interpretedTitle.versionCharacteristics,
        );
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

        if (relinkOnly && match.song == null) {
          return ImportResult(
            status: ImportResultStatus.skipped,
            filePath: candidate.filePath,
            skipReason: ImportSkipReason.notInLibrary,
          );
        }

        var artist = match.artist;

        if (artist == null) {
          artist = EntityFactory.createArtist(
            name: effectiveMetadata.artistName,
            now: timestamp,
          );

          await artistRepository.create(artist);

          final artistOrigins = effectiveOrigins;
          if (artistOrigins != null) {
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.artist,
              entityId: artist.id,
              fieldName: MetadataFields.artistName,
              source: artistOrigins.artistName,
              updatedAt: timestamp,
            );
          }

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

            final albumArtistOrigins = effectiveOrigins;
            if (albumArtistOrigins != null) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.artist,
                entityId: albumArtist.id,
                fieldName: MetadataFields.artistName,
                source: albumArtistOrigins.albumArtistName,
                updatedAt: timestamp,
              );
            }

            if (syncUserId != null && syncUserId.isNotEmpty) {
              await localSyncRepository.recordUpsert(
                userId: syncUserId,
                entityType: CloudDataEntity.artist,
                entityId: albumArtist.id,
              );
            }
          }
        }

        // "locket (Deluxe)" names the album "locket"; the edition keeps the
        // full title.
        final qualifiedAlbum = EditionTitleParser.parse(metadata.albumTitle);

        var album = match.album;

        if (album == null) {
          album = EntityFactory.createAlbum(
            artistId: albumArtist.id,
            title: qualifiedAlbum?.baseTitle ?? metadata.albumTitle,
            now: timestamp,
          );

          await albumRepository.create(album);

          final albumOrigins = effectiveOrigins;
          if (albumOrigins != null) {
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.album,
              entityId: album.id,
              fieldName: MetadataFields.albumArtist,
              source: albumOrigins.albumArtistName,
              updatedAt: timestamp,
            );
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.album,
              entityId: album.id,
              fieldName: MetadataFields.albumTitle,
              source: albumOrigins.albumTitle,
              updatedAt: timestamp,
            );
          }

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
          // The album's first edition is its primary one; a later edition
          // (a Deluxe joining its Standard) never takes that over.
          final albumHasEditions = (await editionRepository.getByAlbumId(
            album.id,
          )).isNotEmpty;

          edition = EntityFactory.createAlbumEdition(
            albumId: album.id,
            title: effectiveMetadata.albumTitle,
            type:
                match.newEditionType ??
                qualifiedAlbum?.type ??
                AlbumEditionType.standard,
            isPrimary: !albumHasEditions,
            releaseDate: metadata.releaseDate,
            genre: metadata.genre,
            now: timestamp,
          );

          await editionRepository.create(edition);

          final editionOrigins = effectiveOrigins;
          if (editionOrigins != null) {
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.albumEdition,
              entityId: edition.id,
              fieldName: MetadataFields.editionTitle,
              source: editionOrigins.albumTitle,
              updatedAt: timestamp,
            );

            if (edition.releaseDate != null) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.albumEdition,
                entityId: edition.id,
                fieldName: MetadataFields.editionReleaseDate,
                source: editionOrigins.releaseDate,
                updatedAt: timestamp,
              );
            }

            if (edition.genre != null && edition.genre!.trim().isNotEmpty) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.albumEdition,
                entityId: edition.id,
                fieldName: MetadataFields.editionGenre,
                source: editionOrigins.genre,
                updatedAt: timestamp,
              );
            }
          }

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
            title: effectiveMetadata.title,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            durationSeconds: metadata.durationSeconds,
            isSingle: metadata.isSingle,
            featuredArtists: effectiveMetadata.featuredArtists,
            versionLabel: interpretedTitle.versionLabel,
            versionCharacteristics: interpretedTitle.versionCharacteristics,
            now: timestamp,
          );

          await songRepository.create(song);
          final songOrigins = effectiveOrigins;
          if (songOrigins != null) {
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songArtist,
              source: songOrigins.artistName,
              updatedAt: timestamp,
            );

            final albumRelationshipSource = _combinedSource(
              songOrigins.albumArtistName,
              songOrigins.albumTitle,
            );

            if (albumRelationshipSource != null) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.song,
                entityId: song.id,
                fieldName: MetadataFields.songAlbum,
                source: albumRelationshipSource,
                updatedAt: timestamp,
              );
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.song,
                entityId: song.id,
                fieldName: MetadataFields.songAlbumEdition,
                source: albumRelationshipSource,
                updatedAt: timestamp,
              );
            }

            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songTitle,
              source: songOrigins.title,
              updatedAt: timestamp,
            );
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songTrackNumber,
              source: songOrigins.trackNumber,
              updatedAt: timestamp,
            );
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songDiscNumber,
              source: songOrigins.discNumber,
              updatedAt: timestamp,
            );
            await _recordImportField(
              service: metadataFieldStateService,
              entityType: MetadataEntityType.song,
              entityId: song.id,
              fieldName: MetadataFields.songIsSingle,
              source: songOrigins.isSingle,
              updatedAt: timestamp,
            );

            final creditSource = _combinedSource(
              songOrigins.artistName,
              songOrigins.featuredArtists,
            );

            if (creditSource != null) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.song,
                entityId: song.id,
                fieldName: MetadataFields.songArtistCredits,
                source: creditSource,
                updatedAt: timestamp,
              );
            }

            if (song.versionLabel != null &&
                song.versionLabel!.trim().isNotEmpty) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.song,
                entityId: song.id,
                fieldName: MetadataFields.songVersionLabel,
                source: songOrigins.title,
                updatedAt: timestamp,
              );
            }

            if (song.versionCharacteristics.isNotEmpty) {
              await _recordImportField(
                service: metadataFieldStateService,
                entityType: MetadataEntityType.song,
                entityId: song.id,
                fieldName: MetadataFields.songVersionCharacteristics,
                source: songOrigins.title,
                updatedAt: timestamp,
              );
            }
          }

          final existingEditionMemberships = await albumEditionTrackRepository
              .getByEditionId(edition.id);

          final nextSortPosition = existingEditionMemberships.isEmpty
              ? 0
              : existingEditionMemberships
                        .map((membership) => membership.sortPosition)
                        .reduce((left, right) => left > right ? left : right) +
                    1;

          await albumEditionTrackRepository.create(
            AlbumEditionTrack(
              albumEditionId: edition.id,
              songId: song.id,
              discNumber: song.discNumber,
              trackNumber: song.trackNumber,
              sortPosition: nextSortPosition,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );

          final structuredCredits =
              await SongArtistCreditService.replaceCreditsWithRepositories(
                artistRepository: artistRepository,
                songRepository: songRepository,
                songArtistCreditRepository: songArtistCreditRepository,
                onArtistCreated:
                    effectiveOrigins == null &&
                        (syncUserId == null || syncUserId.isEmpty)
                    ? null
                    : (artistId) async {
                        final origins = effectiveOrigins;

                        if (origins != null) {
                          await _recordImportField(
                            service: metadataFieldStateService,
                            entityType: MetadataEntityType.artist,
                            entityId: artistId,
                            fieldName: MetadataFields.artistName,
                            source: origins.featuredArtists,
                            updatedAt: timestamp,
                          );
                        }

                        if (syncUserId != null && syncUserId.isNotEmpty) {
                          await localSyncRepository.recordUpsert(
                            userId: syncUserId,
                            entityType: CloudDataEntity.artist,
                            entityId: artistId,
                          );
                        }
                      },
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
            alternateRecording: match.alternateRecordingOf != null,
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

        // The recording is already in the library. If this file's edition
        // doesn't list it yet (a Standard track on the Deluxe), it does now,
        // at the file's disc and track position.
        final songMemberships = await albumEditionTrackRepository.getBySongId(
          song.id,
        );
        final sharedWithEdition = !songMemberships.any(
          (membership) => membership.albumEditionId == edition!.id,
        );

        if (sharedWithEdition) {
          final editionMemberships = await albumEditionTrackRepository
              .getByEditionId(edition.id);

          await albumEditionTrackRepository.create(
            AlbumEditionTrack(
              albumEditionId: edition.id,
              songId: song.id,
              discNumber: metadata.discNumber,
              trackNumber: metadata.trackNumber,
              sortPosition: editionMemberships.isEmpty
                  ? 0
                  : editionMemberships
                            .map((membership) => membership.sortPosition)
                            .reduce((a, b) => a > b ? a : b) +
                        1,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
        }

        final existingSongBindings = await bindingRepository.getBySongId(
          song.id,
        );

        final availableBindings = existingSongBindings
            .where((binding) => binding.isAvailable)
            .toList(growable: false);

        if (availableBindings.isNotEmpty) {
          // Another file already plays this recording. Nothing is written for
          // the copy; the result says which song it duplicates.
          return ImportResult(
            status: ImportResultStatus.skipped,
            filePath: candidate.filePath,
            songId: song.id,
            skipReason: sharedWithEdition
                ? ImportSkipReason.sharedWithEdition
                : ImportSkipReason.duplicateRecording,
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
    } on LibraryMutationUnavailable {
      // A restore refused the import: an interruption, not a failed file.
      rethrow;
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

  Future<void> _recordImportField({
    required MetadataFieldStateService service,
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required ImportMetadataFieldSource source,
    required DateTime updatedAt,
  }) async {
    final authority = switch (source) {
      ImportMetadataFieldSource.embedded => MetadataAuthority.imported,
      ImportMetadataFieldSource.fallback => MetadataAuthority.inferred,
    };

    final provenanceSource = switch (source) {
      ImportMetadataFieldSource.embedded =>
        MetadataProvenanceSource.embeddedTag,
      ImportMetadataFieldSource.fallback => MetadataProvenanceSource.filename,
    };

    await service.record(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      authority: authority,
      source: provenanceSource,
      updatedAt: updatedAt,
    );
  }

  ImportMetadataFieldSource? _combinedSource(
    ImportMetadataFieldSource first,
    ImportMetadataFieldSource second,
  ) {
    if (first == second) {
      return first;
    }

    return null;
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
    required bool alternateRecording,
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

    if (alternateRecording) {
      reasons.add(ImportReviewReason.alternateRecording);
    }

    return reasons;
  }
}
