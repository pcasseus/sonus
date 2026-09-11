import 'import_batch_item.dart';

enum ImportBatchStatus { pending, running, completed }

class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.items,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.status = ImportBatchStatus.pending,
  });

  final String id;
  final List<ImportBatchItem> items;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final ImportBatchStatus status;

  int get totalCount => items.length;

  int get completedCount => items.where((item) => item.isComplete).length;

  int get pendingCount => totalCount - completedCount;

  int get importedCount => items
      .where((item) => item.status == ImportBatchItemStatus.imported)
      .length;

  int get relinkedCount => items
      .where((item) => item.status == ImportBatchItemStatus.relinked)
      .length;

  int get skippedCount => items
      .where((item) => item.status == ImportBatchItemStatus.skipped)
      .length;

  int get failedCount =>
      items.where((item) => item.status == ImportBatchItemStatus.failed).length;

  double get progress {
    if (totalCount == 0) {
      return 1;
    }

    return completedCount / totalCount;
  }

  ImportBatch start(DateTime timestamp) {
    return ImportBatch(
      id: id,
      items: items,
      createdAt: createdAt,
      startedAt: timestamp,
      completedAt: completedAt,
      status: ImportBatchStatus.running,
    );
  }

  ImportBatch withItems(List<ImportBatchItem> updatedItems) {
    return ImportBatch(
      id: id,
      items: List.unmodifiable(updatedItems),
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: completedAt,
      status: status,
    );
  }

  ImportBatch complete(DateTime timestamp) {
    return ImportBatch(
      id: id,
      items: items,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: timestamp,
      status: ImportBatchStatus.completed,
    );
  }
}
