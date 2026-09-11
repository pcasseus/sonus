import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/domain/entities/import_batch_record.dart';

void main() {
  test('calculates batch outcome counts', () {
    final batch = ImportBatchRecord(
      id: 'batch_1',
      status: ImportBatchRecordStatus.running,
      totalCount: 6,
      importedCount: 2,
      relinkedCount: 1,
      skippedCount: 1,
      failedCount: 1,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    expect(batch.successfulCount, 3);
    expect(batch.processedCount, 5);
    expect(batch.pendingCount, 1);
    expect(batch.hasFailures, isTrue);
    expect(batch.isComplete, isFalse);
  });

  test('reports completed batch when all items are processed', () {
    final batch = ImportBatchRecord(
      id: 'batch_complete',
      status: ImportBatchRecordStatus.completed,
      totalCount: 4,
      importedCount: 2,
      relinkedCount: 1,
      skippedCount: 1,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
      startedAt: DateTime.utc(2026, 9, 10, 12),
      completedAt: DateTime.utc(2026, 9, 10, 12, 5),
    );

    expect(batch.processedCount, 4);
    expect(batch.pendingCount, 0);
    expect(batch.isComplete, isTrue);
  });

  test('batch identity is based on permanent id', () {
    final first = ImportBatchRecord(
      id: 'batch_same',
      status: ImportBatchRecordStatus.pending,
      totalCount: 1,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    final second = ImportBatchRecord(
      id: 'batch_same',
      status: ImportBatchRecordStatus.completed,
      totalCount: 1,
      importedCount: 1,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
