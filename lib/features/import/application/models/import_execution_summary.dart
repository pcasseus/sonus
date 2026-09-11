import 'import_batch.dart';

class ImportExecutionSummary {
  const ImportExecutionSummary({
    required this.batchId,
    required this.totalCount,
    required this.importedCount,
    required this.relinkedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  final String batchId;
  final int totalCount;
  final int importedCount;
  final int relinkedCount;
  final int skippedCount;
  final int failedCount;

  int get successfulCount => importedCount + relinkedCount;

  int get processedCount =>
      importedCount + relinkedCount + skippedCount + failedCount;

  bool get hasFailures => failedCount > 0;

  bool get isComplete => processedCount == totalCount;

  factory ImportExecutionSummary.fromBatch(ImportBatch batch) {
    return ImportExecutionSummary(
      batchId: batch.id,
      totalCount: batch.totalCount,
      importedCount: batch.importedCount,
      relinkedCount: batch.relinkedCount,
      skippedCount: batch.skippedCount,
      failedCount: batch.failedCount,
    );
  }
}
