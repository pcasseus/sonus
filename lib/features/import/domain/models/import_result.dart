import 'import_failure.dart';

enum ImportResultStatus { imported, relinked, skipped, failed }

class ImportResult {
  const ImportResult({
    required this.status,
    required this.filePath,
    this.songId,
    this.failure,
  });

  final ImportResultStatus status;
  final String filePath;
  final String? songId;
  final ImportFailure? failure;

  bool get succeeded {
    return status == ImportResultStatus.imported ||
        status == ImportResultStatus.relinked;
  }

  bool get failed => status == ImportResultStatus.failed;
}
