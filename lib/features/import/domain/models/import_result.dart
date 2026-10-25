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
