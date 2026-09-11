import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/data/mappers/import_batch_record_row_mapper.dart';
import 'package:sonus_next/features/import/domain/entities/import_batch_record.dart';

void main() {
  test('maps import batch record to database row and back', () {
    final batch = ImportBatchRecord(
      id: 'batch_mapper',
      status: ImportBatchRecordStatus.completed,
      totalCount: 5,
      importedCount: 2,
      relinkedCount: 1,
      skippedCount: 1,
      failedCount: 1,
      createdAt: DateTime.utc(2026, 9, 10, 12),
      startedAt: DateTime.utc(2026, 9, 10, 12, 1),
      completedAt: DateTime.utc(2026, 9, 10, 12, 5),
    );

    final row = ImportBatchRecordRowMapper.toRow(batch);

    expect(row['id'], 'batch_mapper');
    expect(row['status'], 'completed');
    expect(row['total_count'], 5);
    expect(row['imported_count'], 2);
    expect(row['relinked_count'], 1);
    expect(row['skipped_count'], 1);
    expect(row['failed_count'], 1);

    final restored = ImportBatchRecordRowMapper.fromRow(row);

    expect(restored.id, batch.id);
    expect(restored.status, batch.status);
    expect(restored.totalCount, batch.totalCount);
    expect(restored.importedCount, batch.importedCount);
    expect(restored.relinkedCount, batch.relinkedCount);
    expect(restored.skippedCount, batch.skippedCount);
    expect(restored.failedCount, batch.failedCount);
    expect(restored.createdAt, batch.createdAt);
    expect(restored.startedAt, batch.startedAt);
    expect(restored.completedAt, batch.completedAt);
  });

  test('preserves nullable lifecycle timestamps', () {
    final batch = ImportBatchRecord(
      id: 'batch_pending',
      status: ImportBatchRecordStatus.pending,
      totalCount: 2,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    final restored = ImportBatchRecordRowMapper.fromRow(
      ImportBatchRecordRowMapper.toRow(batch),
    );

    expect(restored.startedAt, isNull);
    expect(restored.completedAt, isNull);
  });

  test('rejects unknown persisted batch status', () {
    expect(
      () => ImportBatchRecordRowMapper.fromRow({
        'id': 'batch_invalid',
        'status': 'invalid',
        'total_count': 0,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': DateTime.utc(2026, 9, 10).toIso8601String(),
        'started_at': null,
        'completed_at': null,
      }),
      throwsA(isA<ArgumentError>()),
    );
  });
}
