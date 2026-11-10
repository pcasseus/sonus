import 'dart:developer' as developer;

import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/file_identity_service.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/application/folders/folder_album_planner.dart';
import 'package:sonus_next/features/import/application/folders/source_folder_key.dart';
import 'package:sonus_next/features/import/application/identity/import_identity_metadata_normalizer.dart';
import 'package:sonus_next/features/import/data/services/possible_recording_store.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_folder_placement.dart';
import 'package:sonus_next/features/import/domain/models/import_scan_snapshot.dart';
import 'package:sonus_next/features/import/application/metadata/track_title_version_interpreter.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';
import 'package:sonus_next/features/import/domain/repositories/media_file_binding_repository.dart';

/// What a batch pre-pass learned about one new file: its tags, and the
/// folder album it belongs to (SN-45).
class PreparedImport {
  const PreparedImport({
    required this.metadata,
    this.placement,
    this.folderRecordings = const [],
  });

  final ResolvedMetadata metadata;
  final ImportFolderPlacement? placement;

  /// Every new file of the same folder in this batch, as evidence that the
  /// folder holds the same recordings as an album already in the library
  /// (App Update 1.2: a copied or moved folder is not a new album).
  final List<FolderRecording> folderRecordings;
}

class LibraryImportService {
  const LibraryImportService({
    required this.metadataResolver,
    required this.atomicImporter,
    this.mediaFileBindingRepository,
    this.lyricsIngestionService,
    this.possibleRecordingStore,
    this.fileIdentityService,
  });

  final MetadataResolver metadataResolver;
  final AtomicLibraryImporter atomicImporter;
  final MediaFileBindingRepository? mediaFileBindingRepository;
  final LyricsIngestionService? lyricsIngestionService;

  /// Where possible different recordings wait for the user's decision.
  final PossibleRecordingStore? possibleRecordingStore;

  /// Recognises renamed, moved, rewritten and retagged files by their audio
  /// (BUG-09). Without one, files are matched by location and tags only.
  final FileIdentityService? fileIdentityService;

  /// BUG-09: settles, before the batch imports, every file known by its
  /// audio (see FileIdentityService). Never fails the batch: a file whose
  /// check fails imports as before.
  Future<FileIdentityPlan> planIdentities(
    List<ImportCandidate> candidates, {
    required Map<String, PreparedImport> prepared,
    ImportScanSnapshot? scan,
    DateTime? now,
  }) async {
    final service = fileIdentityService;
    if (service == null) return FileIdentityPlan.empty;
    return service.plan(
      candidates,
      scan: scan,
      preparedMetadata: {
        for (final MapEntry(:key, :value) in prepared.entries)
          key: value.metadata,
      },
      now: now ?? DateTime.now(),
    );
  }

  /// SN-45 pre-pass: reads the tags of the batch's new files once and
  /// decides one album per folder (see FolderAlbumPlanner). Files already
  /// in the library and unreadable files are left out; [importCandidate]
  /// handles them exactly as before.
  Future<Map<String, PreparedImport>> prepareFolders(
    List<ImportCandidate> candidates, {
    ImportScanSnapshot? scan,
  }) async {
    final resolved = <String, (ImportCandidate, ResolvedMetadata)>{};

    for (final candidate in candidates) {
      final normalizedPath = TextNormalizer.normalizePath(candidate.filePath);

      try {
        final known = await mediaFileBindingRepository?.getByNormalizedPath(
          normalizedPath,
        );
        if (known != null) continue;

        resolved[normalizedPath] = (
          candidate,
          await metadataResolver.resolve(candidate),
        );
      } on LibraryMutationUnavailable {
        rethrow;
      } catch (_) {
        // Reported by importCandidate when it reads the file itself.
      }
    }

    final placements = FolderAlbumPlanner.plan([
      for (final MapEntry(key: path, value: (candidate, metadata))
          in resolved.entries)
        FolderPlanEntry(
          normalizedPath: path,
          folderKey: SourceFolderKey.of(candidate.filePath),
          folderName: SourceFolderKey.folderName(
            candidate.metadataFallbackPath ?? candidate.filePath,
          ),
          metadata: metadata.metadata,
        ),
    ]);

    // The same title reading as the importer's (feature credits, version
    // qualifiers), so the evidence compares like with like.
    const identityNormalizer = ImportIdentityMetadataNormalizer();
    const titleInterpreter = TrackTitleVersionInterpreter();
    final recordingsByFolder = <String, List<FolderRecording>>{};
    for (final MapEntry(key: path, value: (candidate, resolvedMetadata))
        in resolved.entries) {
      final folderKey = placements[path]?.folderKey;
      if (folderKey == null) continue;
      final metadata = identityNormalizer.normalize(
        candidate: candidate,
        metadata: resolvedMetadata.metadata,
      );
      final title = titleInterpreter.interpret(metadata.title);
      (recordingsByFolder[folderKey] ??= []).add(
        FolderRecording(
          canonicalTitle: TextNormalizer.canonicalize(title.title),
          versionLabel: title.versionLabel,
          discNumber: metadata.discNumber,
          trackNumber: metadata.trackNumber,
          durationSeconds: metadata.durationSeconds,
        ),
      );
    }

    return {
      for (final MapEntry(key: path, value: (_, metadata)) in resolved.entries)
        path: PreparedImport(
          metadata: metadata,
          placement: placements[path],
          folderRecordings: List.unmodifiable(
            recordingsByFolder[placements[path]?.folderKey] ?? const [],
          ),
        ),
    };
  }

  /// Imports one file. [separateFrom] keeps a possible different recording
  /// of that song as its own song (see AtomicLibraryImporter.import).
  Future<ImportResult> importCandidate(
    ImportCandidate candidate, {
    DateTime? now,
    PreparedImport? prepared,
    String? separateFrom,
    ImportScanSnapshot? scan,
    FileIdentityPlan identityPlan = FileIdentityPlan.empty,
  }) async {
    final timestamp = now ?? DateTime.now();
    final normalizedPath = TextNormalizer.normalizePath(candidate.filePath);

    // Settled by its audio before the batch: relinked, a copy, a deleted
    // recording, or waiting in Import Review.
    final settled = identityPlan.results[normalizedPath];
    if (settled != null) {
      return _ingestLyrics(candidate, settled);
    }

    final result = await _importCandidate(
      candidate,
      timestamp: timestamp,
      normalizedPath: normalizedPath,
      prepared: prepared,
      separateFrom: separateFrom,
      scan: scan,
    );

    // The audio identity read for this file stays with its binding, so the
    // file is recognised wherever it goes next.
    final reading = identityPlan.readings[normalizedPath];
    final service = fileIdentityService;
    if (reading != null &&
        service != null &&
        (result.succeeded || result.skipReason == ImportSkipReason.knownFile)) {
      try {
        await service.keep(normalizedPath, reading);
      } on LibraryMutationUnavailable {
        rethrow;
      } catch (error, stackTrace) {
        developer.log(
          'Audio identity could not be kept (${error.runtimeType})',
          name: 'sonus.import.file_identity',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return result;
  }

  Future<ImportResult> _importCandidate(
    ImportCandidate candidate, {
    required DateTime timestamp,
    required String normalizedPath,
    required PreparedImport? prepared,
    required String? separateFrom,
    required ImportScanSnapshot? scan,
  }) async {
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
            skipReason: wasAvailable ? ImportSkipReason.knownFile : null,
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
    final AudioMetadata metadata;
    final MetadataSource metadataSource;

    try {
      final resolvedMetadata =
          prepared?.metadata ?? await metadataResolver.resolve(candidate);
      metadata = resolvedMetadata.metadata;
      metadataSource = resolvedMetadata.source;

      imported = await atomicImporter.import(
        candidate: candidate,
        metadata: metadata,
        metadataSource: resolvedMetadata.source,
        metadataOrigins: resolvedMetadata.origins,
        folderPlacement: prepared?.placement,
        folderRecordings: prepared?.folderRecordings ?? const [],
        separateFrom: separateFrom,
        scan: scan,
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

    return _ingestLyrics(
      candidate,
      await _notePossibleRecording(
        candidate,
        normalizedPath: normalizedPath,
        metadata: metadata,
        metadataSource: metadataSource,
        result: imported,
        timestamp: timestamp,
      ),
    );
  }

  /// Keeps a possible different recording on the device's pending list, once
  /// per path, unless the user said this file is the same recording as the
  /// song: it is then reported as a copy. A file that imported leaves the
  /// list. The import result itself never depends on the list.
  Future<ImportResult> _notePossibleRecording(
    ImportCandidate candidate, {
    required String normalizedPath,
    required AudioMetadata metadata,
    required MetadataSource metadataSource,
    required ImportResult result,
    required DateTime timestamp,
  }) async {
    final store = possibleRecordingStore;
    final songId = result.songId;

    if (store == null) return result;

    try {
      if (result.succeeded) {
        await store.remove(normalizedPath);
        return result;
      }

      if (result.skipReason == ImportSkipReason.awaitingFileReview &&
          songId != null) {
        // BUG-09: matches a song whose file is gone by its tags alone.
        await store.upsert(
          _pending(
            candidate,
            normalizedPath: normalizedPath,
            songId: songId,
            metadata: metadata,
            metadataSource: metadataSource,
            timestamp: timestamp,
            kind: PendingFileReviewKind.possibleReplacedFile,
          ),
        );
        return result;
      }

      if (result.skipReason != ImportSkipReason.possibleAlternateRecording ||
          songId == null) {
        return result;
      }

      if (await store.isSameRecording(
        normalizedPath: normalizedPath,
        candidateSongId: songId,
        durationSeconds: metadata.durationSeconds,
      )) {
        return ImportResult(
          status: ImportResultStatus.skipped,
          filePath: result.filePath,
          songId: songId,
          skipReason: ImportSkipReason.duplicateRecording,
        );
      }

      await store.upsert(
        _pending(
          candidate,
          normalizedPath: normalizedPath,
          songId: songId,
          metadata: metadata,
          metadataSource: metadataSource,
          timestamp: timestamp,
        ),
      );
    } catch (_) {
      // The pending list is a convenience on this device; the file stays
      // out of the library either way and is reported again on a rescan.
    }

    return result;
  }

  static PendingPossibleRecording _pending(
    ImportCandidate candidate, {
    required String normalizedPath,
    required String songId,
    required AudioMetadata metadata,
    required MetadataSource metadataSource,
    required DateTime timestamp,
    PendingFileReviewKind kind =
        PendingFileReviewKind.possibleDifferentRecording,
  }) => PendingPossibleRecording(
    normalizedPath: normalizedPath,
    filePath: candidate.filePath.trim(),
    candidateSongId: songId,
    title: metadata.title,
    artistName: metadata.artistName,
    albumTitle: metadata.albumTitle,
    discNumber: metadata.discNumber,
    trackNumber: metadata.trackNumber,
    durationSeconds: metadata.durationSeconds,
    firstSeenAt: timestamp.toUtc(),
    metadataFallbackPath: candidate.metadataFallbackPath,
    sourceId: candidate.sourceId,
    metadataSource: metadataSource,
    kind: kind,
  );

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
        result.failed ||
        // A copy's sidecar belongs to the copy, not to the song it duplicates,
        // including another edition's copy of it and a possible different
        // recording that was kept out of the library.
        result.skipReason == ImportSkipReason.duplicateRecording ||
        result.skipReason == ImportSkipReason.sharedWithEdition ||
        result.skipReason == ImportSkipReason.possibleAlternateRecording ||
        result.skipReason == ImportSkipReason.awaitingFileReview ||
        result.skipReason == ImportSkipReason.deletedFromLibrary) {
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
