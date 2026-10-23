import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/repositories/media_file_binding_repository.dart';

class LibraryImportService {
  const LibraryImportService({
    required this.metadataResolver,
    required this.atomicImporter,
    this.mediaFileBindingRepository,
    this.lyricsIngestionService,
  });

  final MetadataResolver metadataResolver;
  final AtomicLibraryImporter atomicImporter;
  final MediaFileBindingRepository? mediaFileBindingRepository;
  final LyricsIngestionService? lyricsIngestionService;

  Future<ImportResult> importCandidate(
    ImportCandidate candidate, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final normalizedPath = TextNormalizer.normalizePath(candidate.filePath);

    final bindingRepository = mediaFileBindingRepository;

    // A restore rejection is an interruption, never an item failure: it
    // propagates unchanged from every write below. Lyrics are ingested
    // after, not inside, the error handling, for the same reason.
    if (bindingRepository != null) {
      ImportResult? refreshed;

      try {
        final existingBinding = await bindingRepository.getByNormalizedPath(
          normalizedPath,
        );

        if (existingBinding != null) {
          final wasAvailable = existingBinding.isAvailable;

          final updatedBinding = existingBinding.copyWith(
            filePath: candidate.filePath.trim(),
            normalizedPath: normalizedPath,
            sourceId: candidate.sourceId ?? existingBinding.sourceId,
            isAvailable: true,
            lastSeenAt: timestamp,
            updatedAt: timestamp,
          );

          await bindingRepository.save(updatedBinding);

          refreshed = ImportResult(
            status: wasAvailable
                ? ImportResultStatus.skipped
                : ImportResultStatus.relinked,
            filePath: candidate.filePath,
            songId: existingBinding.songId,
          );
        }
      } on LibraryMutationUnavailable {
        rethrow;
      } catch (error) {
        return ImportResult(
          status: ImportResultStatus.failed,
          filePath: candidate.filePath,
          failure: ImportFailure(
            type: ImportFailureType.persistenceFailure,
            message: 'Unable to update media file binding: $error',
          ),
        );
      }

      if (refreshed != null) {
        return _ingestLyrics(candidate, refreshed);
      }
    }

    final ImportResult imported;

    try {
      final resolvedMetadata = await metadataResolver.resolve(candidate);

      imported = await atomicImporter.import(
        candidate: candidate,
        metadata: resolvedMetadata.metadata,
        metadataSource: resolvedMetadata.source,
        metadataOrigins: resolvedMetadata.origins,
        now: timestamp,
      );
    } on LibraryMutationUnavailable {
      rethrow;
    } catch (error) {
      return ImportResult(
        status: ImportResultStatus.failed,
        filePath: candidate.filePath,
        failure: ImportFailure(
          type: ImportFailureType.metadataUnreadable,
          message: 'Unable to resolve audio metadata: $error',
        ),
      );
    }

    return _ingestLyrics(candidate, imported);
  }

  Future<ImportResult> _ingestLyrics(
    ImportCandidate candidate,
    ImportResult result,
  ) async {
    final service = lyricsIngestionService;
    final lyricsPath = candidate.lyricsPath?.trim();
    final songId = result.songId?.trim();

    if (service == null ||
        lyricsPath == null ||
        lyricsPath.isEmpty ||
        songId == null ||
        songId.isEmpty ||
        result.failed) {
      return result;
    }

    try {
      await service.ingest(candidate: candidate, songId: songId);
    } on LibraryMutationUnavailable {
      // A restore refused the write. Surface it so the batch stops; the
      // committed song stands and a later rescan ingests the sidecar.
      rethrow;
    } catch (_) {
      // Sidecar lyrics are optional enrichment. Audio import/binding success
      // must not be converted into a failed import if lyrics cannot be read.
    }

    return result;
  }
}
