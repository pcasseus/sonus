/// Why a file could not be read for import (SN-50 §4), so callers can tell
/// a missing file from one Sonus may no longer read and from one whose
/// tags cannot be read.
sealed class ImportFileFailure implements Exception {
  String get message;
}

/// No file exists at the path or content URI.
class ImportFileMissing implements ImportFileFailure {
  const ImportFileMissing(this.message);

  @override
  final String message;

  @override
  String toString() => 'ImportFileMissing: $message';
}

/// Sonus lost access to the file's folder (Android SAF permission).
class ImportFileAccessDenied implements ImportFileFailure {
  const ImportFileAccessDenied(this.message);

  @override
  final String message;

  @override
  String toString() => 'ImportFileAccessDenied: $message';
}

/// The file is present but has no readable tags. Still a [FormatException],
/// as before, for callers that handle that.
class ImportTagsUnreadable extends FormatException
    implements ImportFileFailure {
  const ImportTagsUnreadable([super.message = '']);
}
