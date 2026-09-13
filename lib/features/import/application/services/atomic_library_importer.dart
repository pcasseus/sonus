import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/identity/library_identity_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding_factory.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
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
        final bindingRepository = SqliteMediaFileBindingRepository(
          MediaFileBindingDao(transaction),
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

        final match = await resolver.resolve(metadata);

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
            name: metadata.artistName,
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

        var album = match.album;

        if (album == null) {
          album = EntityFactory.createAlbum(
            artistId: artist.id,
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
            title: metadata.albumTitle,
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
            durationSeconds: metadata.durationSeconds,
            isSingle: metadata.isSingle,
            featuredArtists: metadata.featuredArtists,
            now: timestamp,
          );

          await songRepository.create(song);

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
}
