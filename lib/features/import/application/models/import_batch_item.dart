import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_result.dart';

enum ImportBatchItemStatus { pending, imported, relinked, skipped, failed }

class ImportBatchItem {
  const ImportBatchItem({required this.candidate, this.result});

  final ImportCandidate candidate;
  final ImportResult? result;

  bool get isComplete => result != null;

  ImportBatchItemStatus get status {
    final currentResult = result;

    if (currentResult == null) {
      return ImportBatchItemStatus.pending;
    }

    switch (currentResult.status) {
      case ImportResultStatus.imported:
        return ImportBatchItemStatus.imported;
      case ImportResultStatus.relinked:
        return ImportBatchItemStatus.relinked;
      case ImportResultStatus.skipped:
        return ImportBatchItemStatus.skipped;
      case ImportResultStatus.failed:
        return ImportBatchItemStatus.failed;
    }
  }

  ImportBatchItem completeWith(ImportResult importResult) {
    return ImportBatchItem(candidate: candidate, result: importResult);
  }
}
