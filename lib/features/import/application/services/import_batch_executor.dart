import '../models/import_batch.dart';
import '../models/import_batch_item.dart';
import '../models/import_execution_summary.dart';
import '../../domain/entities/import_batch_record.dart';
import '../../domain/repositories/import_batch_repository.dart';
import 'import_batch_runner.dart';
import 'library_import_service.dart';

class ImportBatchExecutor implements ImportBatchRunner {
  const ImportBatchExecutor({
    required this.libraryImportService,
    required this.batchRepository,
  });

  final LibraryImportService libraryImportService;
  final ImportBatchRepository batchRepository;

  @override
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    if (batch.status != ImportBatchStatus.pending) {
      throw StateError(
        'Import batch must be pending before execution: ${batch.id}',
      );
    }

    await batchRepository.create(_recordFromBatch(batch));

    final executionStartedAt = startedAt ?? DateTime.now();

    var currentBatch = batch.start(executionStartedAt);

    await batchRepository.save(_recordFromBatch(currentBatch));
    onProgress?.call(currentBatch);

    for (var index = 0; index < currentBatch.items.length; index++) {
      final currentItem = currentBatch.items[index];

      final result = await libraryImportService.importCandidate(
        currentItem.candidate,
        now: executionStartedAt,
      );

      final updatedItems = List<ImportBatchItem>.of(currentBatch.items);
      updatedItems[index] = currentItem.completeWith(result);

      currentBatch = currentBatch.withItems(updatedItems);

      await batchRepository.save(_recordFromBatch(currentBatch));
      onProgress?.call(currentBatch);
    }

    currentBatch = currentBatch.complete(completedAt ?? DateTime.now());

    await batchRepository.save(_recordFromBatch(currentBatch));
    onProgress?.call(currentBatch);

    return ImportExecutionSummary.fromBatch(currentBatch);
  }

  ImportBatchRecord _recordFromBatch(ImportBatch batch) {
    return ImportBatchRecord(
      id: batch.id,
      status: _recordStatus(batch.status),
      totalCount: batch.totalCount,
      importedCount: batch.importedCount,
      relinkedCount: batch.relinkedCount,
      skippedCount: batch.skippedCount,
      failedCount: batch.failedCount,
      createdAt: batch.createdAt,
      startedAt: batch.startedAt,
      completedAt: batch.completedAt,
    );
  }

  ImportBatchRecordStatus _recordStatus(ImportBatchStatus status) {
    switch (status) {
      case ImportBatchStatus.pending:
        return ImportBatchRecordStatus.pending;
      case ImportBatchStatus.running:
        return ImportBatchRecordStatus.running;
      case ImportBatchStatus.completed:
        return ImportBatchRecordStatus.completed;
    }
  }
}
