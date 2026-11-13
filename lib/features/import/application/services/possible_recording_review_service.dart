import '../../../../core/identity/text_normalizer.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../data/services/possible_recording_store.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_result.dart';
import '../../domain/models/pending_possible_recording.dart';
import '../../domain/models/resolved_metadata.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import '../../domain/services/import_file_probe.dart';
import 'file_identity_service.dart';
import 'library_import_service.dart';

/// A pending possible different recording, with the song it may duplicate
/// (null when that song is no longer in the library).
class PossibleRecordingItem {
  const PossibleRecordingItem({
    required this.entry,
    this.candidate,
    this.candidates = const [],
  });

  final PendingPossibleRecording entry;
  final Song? candidate;

  /// Every song the file may be that is still in the library, in the
  /// entry's order (BUG-09).
  final List<Song> candidates;
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

  /// The file is verifiably missing; it leaves the list (SN-50 W15).
  fileUnavailable,

  /// Sonus can no longer read the file's folder; the file stays listed.
  permissionLost,

  /// The file could not be checked; it stays listed.
  checkFailed,

  /// The song it may duplicate is no longer in the library.
  candidateMissing,

  /// The import failed; the file stays listed.
  failed,

  /// BUG-09: the song now plays this file; its history is unchanged.
  usedForSong,

  /// BUG-09: the changed audio was kept as the same song.
  audioKept,

  /// BUG-09: the song already plays another file; nothing changed.
  songHasFile,

  /// BUG-09: the file or its audio was permanently deleted; nothing changed.
  deletedRecording,
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
    this.fileProbe,
    this.fileIdentityService,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// BUG-09: attaches a replaced file to its song, or keeps changed audio.
  final FileIdentityService? fileIdentityService;

  final PossibleRecordingStore store;
  final LibraryImportService libraryImportService;
  final MediaFileBindingRepository mediaFileBindingRepository;
  final SongRepository songRepository;

  /// Read-only reachability checks (SN-50 §4). Without one, files are only
  /// judged by reading their tags.
  final ImportFileProbe? fileProbe;

  final DateTime Function() _now;

  /// Pending files, oldest first. A file that has since joined the library,
  /// or that is gone from its folder, leaves the list. A file Sonus can no
  /// longer reach for another reason stays listed.
  Future<List<PossibleRecordingItem>> pending() async {
    final items = <PossibleRecordingItem>[];

    for (final entry in await store.getPending()) {
      // A file whose audio changed is in the library by design; any other
      // pending file that is now in the library is settled.
      if (entry.kind != PendingFileReviewKind.audioChanged &&
          await mediaFileBindingRepository.getByNormalizedPath(
                entry.normalizedPath,
              ) !=
              null) {
        await store.remove(entry.normalizedPath);
        continue;
      }

      if (await fileProbe?.probe(entry.filePath) == ImportFileState.missing) {
        await store.remove(entry.normalizedPath);
        continue;
      }

      final candidates = [
        for (final id in entry.candidateSongIds)
          ?await songRepository.getById(id),
      ];
      items.add(
        PossibleRecordingItem(
          entry: entry,
          candidate: await songRepository.getById(entry.candidateSongId),
          candidates: List.unmodifiable(candidates),
        ),
      );
    }

    return List.unmodifiable(items);
  }

  /// Imports the file as its own song, flagged for review, after checking
  /// it again. A file that is missing, unreadable or already imported, or
  /// whose song is gone, leaves the list and nothing is written. A file
  /// Sonus lost permission to read, or could not check, stays listed.
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

    switch (await fileProbe?.probe(entry.filePath)) {
      case ImportFileState.missing:
        await store.remove(path);
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.fileUnavailable,
        );
      case ImportFileState.permissionLost:
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.permissionLost,
        );
      case ImportFileState.unknown:
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.checkFailed,
        );
      case ImportFileState.present || null:
        break;
    }

    // Read the file again, with its folder's album as a scan would.
    final prepared = (await libraryImportService.prepareFolders([
      candidate,
    ]))[path];

    // Nothing came back for the path: absence is not verified, so the file
    // stays listed (SN-50 W15).
    if (prepared == null) {
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.checkFailed,
      );
    }

    // Only a path guess: why the tags were not read decides.
    if (prepared.metadata.source == MetadataSource.fallback) {
      final outcome = switch (prepared.metadata.readFailure) {
        MetadataReadFailure.accessDenied =>
          PossibleRecordingOutcome.permissionLost,
        // Reported from its path in the first place: nothing has changed.
        MetadataReadFailure.tagsUnreadable when entry.recordedFromPath => null,
        MetadataReadFailure.missing => PossibleRecordingOutcome.fileUnavailable,
        // Unreadable tags are not a missing file: it stays listed (SN-50
        // W15, 2026-10-31; round 10 retired it).
        MetadataReadFailure.tagsUnreadable =>
          PossibleRecordingOutcome.checkFailed,
        MetadataReadFailure.other ||
        null => PossibleRecordingOutcome.checkFailed,
      };

      if (outcome == PossibleRecordingOutcome.fileUnavailable) {
        await store.remove(path);
      }
      if (outcome != null) return PossibleRecordingActionResult(outcome);
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

  /// BUG-09: the user said the file is [songId]'s file (one of
  /// [PendingPossibleRecording.candidateSongIds]). Checked again first; the
  /// song keeps its ID, plays, playlists and charts.
  Future<PossibleRecordingActionResult> useFileForSong(
    PendingPossibleRecording entry, {
    required String songId,
  }) async {
    final service = fileIdentityService;
    if (service == null || !entry.candidateSongIds.contains(songId)) {
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.failed,
      );
    }
    final unreachable = await _unreachable(entry);
    if (unreachable != null) return unreachable;

    final outcome = await service.useFileForSong(
      _candidateOf(entry),
      songId: songId,
      now: _now(),
    );
    return _settle(entry, outcome, done: PossibleRecordingOutcome.usedForSong);
  }

  /// BUG-09: the user said a known file whose audio changed is still the
  /// same song.
  Future<PossibleRecordingActionResult> keepChangedAudio(
    PendingPossibleRecording entry,
  ) async {
    final service = fileIdentityService;
    if (service == null) {
      return const PossibleRecordingActionResult(
        PossibleRecordingOutcome.failed,
      );
    }
    final unreachable = await _unreachable(entry);
    if (unreachable != null) return unreachable;

    final outcome = await service.keepChangedAudio(
      _candidateOf(entry),
      now: _now(),
    );
    return _settle(entry, outcome, done: PossibleRecordingOutcome.audioKept);
  }

  ImportCandidate _candidateOf(PendingPossibleRecording entry) =>
      ImportCandidate(
        filePath: entry.filePath,
        normalizedPath: TextNormalizer.normalizePath(entry.filePath),
        discoveredAt: _now(),
        metadataFallbackPath: entry.metadataFallbackPath,
        sourceId: entry.sourceId,
      );

  /// Null when the file can be read now.
  Future<PossibleRecordingActionResult?> _unreachable(
    PendingPossibleRecording entry,
  ) async {
    switch (await fileProbe?.probe(entry.filePath)) {
      case ImportFileState.missing:
        await store.remove(entry.normalizedPath);
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.fileUnavailable,
        );
      case ImportFileState.permissionLost:
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.permissionLost,
        );
      case ImportFileState.unknown:
        return const PossibleRecordingActionResult(
          PossibleRecordingOutcome.checkFailed,
        );
      case ImportFileState.present || null:
        return null;
    }
  }

  Future<PossibleRecordingActionResult> _settle(
    PendingPossibleRecording entry,
    FileReviewDecisionOutcome outcome, {
    required PossibleRecordingOutcome done,
  }) async {
    final result = switch (outcome) {
      FileReviewDecisionOutcome.done => done,
      FileReviewDecisionOutcome.songHasFile =>
        PossibleRecordingOutcome.songHasFile,
      FileReviewDecisionOutcome.songMissing =>
        PossibleRecordingOutcome.candidateMissing,
      FileReviewDecisionOutcome.deleted =>
        PossibleRecordingOutcome.deletedRecording,
      FileReviewDecisionOutcome.unreadable =>
        PossibleRecordingOutcome.checkFailed,
      FileReviewDecisionOutcome.notKnown =>
        PossibleRecordingOutcome.alreadyImported,
    };
    if (result != PossibleRecordingOutcome.checkFailed &&
        result != PossibleRecordingOutcome.songHasFile) {
      await store.remove(entry.normalizedPath);
    }
    return PossibleRecordingActionResult(result);
  }

  /// Records that the file is the same recording as its song. Nothing is
  /// written to the library; later scans report the file as a copy.
  Future<void> markSameRecording(PendingPossibleRecording entry) {
    return store.markSameRecording(entry);
  }
}
