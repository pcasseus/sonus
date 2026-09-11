import '../../domain/entities/import_batch_record.dart';

abstract final class ImportBatchRecordRowMapper {
  static Map<String, Object?> toRow(ImportBatchRecord batch) {
    return {
      'id': batch.id,
      'status': batch.status.name,
      'total_count': batch.totalCount,
      'imported_count': batch.importedCount,
      'relinked_count': batch.relinkedCount,
      'skipped_count': batch.skippedCount,
      'failed_count': batch.failedCount,
      'created_at': batch.createdAt.toUtc().toIso8601String(),
      'started_at': batch.startedAt?.toUtc().toIso8601String(),
      'completed_at': batch.completedAt?.toUtc().toIso8601String(),
    };
  }

  static ImportBatchRecord fromRow(Map<String, Object?> row) {
    return ImportBatchRecord(
      id: row['id'] as String,
      status: ImportBatchRecordStatus.values.byName(row['status'] as String),
      totalCount: row['total_count'] as int,
      importedCount: row['imported_count'] as int,
      relinkedCount: row['relinked_count'] as int,
      skippedCount: row['skipped_count'] as int,
      failedCount: row['failed_count'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      startedAt: row['started_at'] == null
          ? null
          : DateTime.parse(row['started_at'] as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
    );
  }
}
