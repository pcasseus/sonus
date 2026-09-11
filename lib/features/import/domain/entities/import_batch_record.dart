enum ImportBatchRecordStatus {
  pending,
  running,
  completed,
}

class ImportBatchRecord {
  const ImportBatchRecord({
    required this.id,
    required this.status,
    required this.totalCount,
    required this.importedCount,
    required this.relinkedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final ImportBatchRecordStatus status;
  final int totalCount;
  final int importedCount;
  final int relinkedCount;
  final int skippedCount;
  final int failedCount;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  int get successfulCount => importedCount + relinkedCount;

  int get processedCount =>
      importedCount + relinkedCount + skippedCount + failedCount;

  int get pendingCount => totalCount - processedCount;

  bool get hasFailures => failedCount > 0;

  bool get isComplete =>
      status == ImportBatchRecordStatus.completed &&
      processedCount == totalCount;

  ImportBatchRecord copyWith({
    String? id,
    ImportBatchRecordStatus? status,
    int? totalCount,
    int? importedCount,
    int? relinkedCount,
    int? skippedCount,
    int? failedCount,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return ImportBatchRecord(
      id: id ?? this.id,
      status: status ?? this.status,
      totalCount: totalCount ?? this.totalCount,
      importedCount: importedCount ?? this.importedCount,
      relinkedCount: relinkedCount ?? this.relinkedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      failedCount: failedCount ?? this.failedCount,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ImportBatchRecord && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}