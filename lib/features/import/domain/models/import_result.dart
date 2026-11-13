import 'import_failure.dart';

enum ImportResultStatus { imported, relinked, skipped, failed }

/// Why a file was skipped.
enum ImportSkipReason {
  /// This exact file is already in the library.
  knownFile,

  /// The same recording is already in the library from another file.
  duplicateRecording,

  /// A relink-only pass found no existing song for the file.
  notInLibrary,

  /// The recording is already in the library from another edition of the
  /// same album; this file's edition now lists it too.
  sharedWithEdition,

  /// Same artist, title, version and album as an existing song, with no
  /// evidence of a different recording, but listed at a different disc and
  /// track position on the same edition. It may be another recording, so the
  /// file is kept out of the library: not bound, not merged and not listed,
  /// so the user can decide in Import Review, from a list kept on this
  /// device (PossibleRecordingStore).
  possibleAlternateRecording,

  /// App Update 1.2: the user permanently deleted this file's song from the
  /// library. The file stays on the device and is not imported again until
  /// the user allows it.
  deletedFromLibrary,

  /// App Update 1.2, BUG-09: the file may be the file of a song already in
  /// the library (renamed, moved, rewritten, or its audio changed), but that
  /// could not be proven from its audio. It waits in Import Review for the
  /// user; no song is created for it meanwhile.
  awaitingFileReview,
}

class ImportResult {
  const ImportResult({
    required this.status,
    required this.filePath,
    this.songId,
    this.failure,
    this.skipReason,
  });

  final ImportResultStatus status;
  final String filePath;
  final String? songId;
  final ImportFailure? failure;

  /// Set when [status] is skipped.
  final ImportSkipReason? skipReason;

  bool get succeeded {
    return status == ImportResultStatus.imported ||
        status == ImportResultStatus.relinked;
  }

  bool get failed => status == ImportResultStatus.failed;
}
