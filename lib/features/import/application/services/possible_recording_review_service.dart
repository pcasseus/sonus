import '../../../../core/identity/text_normalizer.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../data/services/possible_recording_store.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_result.dart';
import '../../domain/models/pending_possible_recording.dart';
import '../../domain/models/resolved_metadata.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import 'library_import_service.dart';

/// A pending possible different recording, with the song it may duplicate
/// (null when that song is no longer in the library).
class PossibleRecordingItem {
  const PossibleRecordingItem({required this.entry, this.candidate});

  final PendingPossibleRecording entry;
  final Song? candidate;
}

enum PossibleRecordingOutcome {
  /// The file is now its own song.
  imported,

  /// The file joined the library another way, as a fresh import decided.
  handledByImport,

  /// The file is still a possible different recording; it stays listed.
  stillPending,

  /// The file is already in the library.
  alreadyImported,

  /// The file is missing or cannot be read.
  fileUnavailable,

  /// The song it may duplicate is no longer in the library.
  candidateMissing,

  /// The import failed; the file stays listed.
  failed,
}

class PossibleRecordingActionResult {
  const PossibleRecordingActionResult(this.outcome, {this.importResult});

  final PossibleRecordingOutcome outcome;
  final ImportResult? importResult;
}

/// The user's decisions on files kept out of the library as possible
/// different recordings. Nothing is merged; the song they may duplicate is
/// never changed.
class PossibleRecordingReviewService {
  PossibleRecordingReviewService({
    required this.store,
    required this.libraryImportService,
    required this.mediaFileBindingRepository,
    required this.songRepository,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PossibleRecordingStore store;
  final LibraryImportService libraryImportService;
  final MediaFileBindingRepository mediaFileBindingRepository;
  final SongRepository songRepository;
  final DateTime Function() _now;

  /// Pending files, oldest first. A file that has since joined the library
  /// leaves the list.
  Future<List<PossibleRecordingItem>> pending() async {
    final items = <PossibleRecordingItem>[];

    for (final entry in await store.getPending()) {
      if (await mediaFileBindingRepository.getByNormalizedPath(
            entry.normalizedPath,
          ) !=
          null) {
        await store.remove(entry.normalizedPath);
        continue;
      }

      items.add(
        PossibleRecordingItem(
          entry: entry,
          candidate: await songRepository.getById(entry.candidateSongId),
        ),
      );
    }

    return List.unmodifiable(items);
  }

  /// Imports the file as its own song, flagged for review, after checking
  /// it again. A file that is missing, unreadable or already imported, or
  /// whose song is gone, leaves the list and nothing is written.
  Future<PossibleRecordingActionResult> importSeparately(
    PendingPossibleRecording entry,
  ) async {
    final path = entry.normalizedPath;

    if (await mediaFileBindingRepository.getByNormalizedPath(path) != null) {
      await store.remove(path);
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.alreadyImported,
      );
    }

    if (await songRepository.getById(entry.candidateSongId) == null) {
      await store.remove(path);
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.candidateMissing,
      );
    }

    final candidate = ImportCandidate(
      filePath: entry.filePath,
      normalizedPath: TextNormalizer.normalizePath(entry.filePath),
      discoveredAt: _now(),
      metadataFallbackPath: entry.metadataFallbackPath,
      sourceId: entry.sourceId,
    );

    // Read the file again, with its folder's album as a scan would. Tags
    // that cannot be read (a path guess only) mean the file is gone.
    final prepared = (await libraryImportService.prepareFolders([
      candidate,
    ]))[path];

    if (prepared == null ||
        prepared.metadata.source == MetadataSource.fallback) {
      await store.remove(path);
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.fileUnavailable,
      );
    }

    final result = await libraryImportService.importCandidate(
      candidate,
      now: _now(),
      prepared: prepared,
      separateFrom: entry.candidateSongId,
    );

    if (result.failed) {
      return PossibleRecordingActionResult(
        PossibleRecordingOutcome.failed,
        importResult: result,
      );
    }

    // Still reported (against another song now): the import listed it again.
    if (result.skipReason == ImportSkipReason.possibleAlternateRecording) {
      return PossibleRecordingActionResult(
        PossibleRecordingOutcome.stillPending,
        importResult: result,
      );
    }

    await store.remove(path);

    final separated =
        result.status == ImportResultStatus.imported &&
        result.songId != entry.candidateSongId;

    return PossibleRecordingActionResult(
      separated
          ? PossibleRecordingOutcome.imported
          : PossibleRecordingOutcome.handledByImport,
      importResult: result,
    );
  }

  /// Records that the file is the same recording as its song. Nothing is
  /// written to the library; later scans report the file as a copy.
  Future<void> markSameRecording(PendingPossibleRecording entry) {
    return store.markSameRecording(entry);
  }
}
