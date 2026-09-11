import '../models/import_batch.dart';
import '../models/import_execution_summary.dart';

typedef ImportBatchProgressCallback = void Function(ImportBatch batch);

abstract interface class ImportBatchRunner {
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  });
}
