class RestoreTableChange {
  const RestoreTableChange({
    required this.table,
    required this.added,
    required this.updated,
    required this.unchanged,
    required this.removed,
  });

  final String table;

  /// Rows only in the backup.
  final int added;

  /// Rows in both with different content.
  final int updated;

  /// Rows in both with identical content.
  final int unchanged;

  /// Local rows the restore will remove.
  final int removed;

  int get restoredRows => added + updated + unchanged;
}

class RestoreDeviceImpact {
  const RestoreDeviceImpact({
    required this.mediaBindingsKept,
    required this.mediaBindingsRemoved,
    required this.importReviewsKept,
    required this.importReviewsRemoved,
    required this.songsWithoutAudio,
    required this.artworkReused,
    required this.artworkInstalled,
  });

  /// Local audio links whose song survives the restore.
  final int mediaBindingsKept;

  /// Local audio links whose song is not in the backup.
  final int mediaBindingsRemoved;

  final int importReviewsKept;
  final int importReviewsRemoved;

  /// Restored songs that will have no available audio on this device.
  final int songsWithoutAudio;

  /// Backup artwork already present locally with identical content.
  final int artworkReused;

  /// Backup artwork that must be installed into device storage.
  final int artworkInstalled;
}

class RestorePlan {
  RestorePlan({
    required this.backupId,
    required List<RestoreTableChange> tables,
    required this.deviceImpact,
    required this.localPortableRowCount,
  }) : tables = List.unmodifiable(tables);

  final String backupId;

  /// One entry per portable table, in coverage-contract order.
  final List<RestoreTableChange> tables;

  final RestoreDeviceImpact deviceImpact;

  /// Portable rows currently on this device.
  final int localPortableRowCount;

  /// Existing portable data must be preserved in a verified safety backup
  /// before it may be replaced.
  bool get requiresSafetyBackup => localPortableRowCount > 0;

  int get totalAdded => tables.fold(0, (sum, t) => sum + t.added);
  int get totalUpdated => tables.fold(0, (sum, t) => sum + t.updated);
  int get totalRemoved => tables.fold(0, (sum, t) => sum + t.removed);

  RestoreTableChange table(String name) =>
      tables.firstWhere((entry) => entry.table == name);
}
