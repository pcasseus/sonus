enum RestoreBlocker {
  /// The backup was created by a different Sonus database schema.
  incompatibleBackupVersion,

  /// The local database is not at the schema this build expects.
  incompatibleLocalDatabase,

  /// Backup rows do not match the local table structure.
  schemaMismatch,

  /// Listening history in the backup belongs to more than one account.
  multipleBackupAccounts,

  /// The backup belongs to a different account than this device.
  accountConflict,

  /// Local changes are still waiting to be synchronized to the cloud.
  pendingSyncWork,

  /// The device does not have enough free space for a safe restore.
  insufficientStorage,

  /// Free space could not be determined on a platform that supports it.
  storageCheckFailed,
}

class RestorePreflight {
  RestorePreflight({
    required List<RestoreBlocker> blockers,
    required this.backupId,
    required this.backupCreatedAtUtc,
    required this.backupDatabaseVersion,
    required Set<String> backupAccountIds,
    required this.localAccountId,
    required this.pendingSyncItemCount,
    required this.hasCloudSyncState,
    required this.estimatedRequiredBytes,
    this.availableBytes,
  }) : blockers = List.unmodifiable(blockers),
       backupAccountIds = Set.unmodifiable(backupAccountIds);

  final List<RestoreBlocker> blockers;

  final String backupId;
  final DateTime backupCreatedAtUtc;
  final int backupDatabaseVersion;

  /// Distinct non-null owners recorded in the backup's listening history.
  final Set<String> backupAccountIds;

  /// The account this device is bound to, if any.
  final String? localAccountId;

  /// Outbox and journal entries that have not reached the cloud yet.
  final int pendingSyncItemCount;

  /// Whether this device holds any cloud sync state (binding, cursors, or
  /// revision baselines). A restore on such a device requires a sync
  /// consistency assessment before normal sync may resume.
  final bool hasCloudSyncState;

  /// Approximate storage a restore needs: extracted and installed artwork,
  /// database growth, and the safety backup of the current library.
  final int estimatedRequiredBytes;

  /// Free space reported by the platform, or null where the platform
  /// cannot report it (free space is then unverified).
  final int? availableBytes;

  bool get isStorageVerified => availableBytes != null;

  bool get canRestore => blockers.isEmpty;

  /// True when the restored library is associated with cloud sync and
  /// sync must stay on hold until consistency has been assessed.
  bool get requiresSyncAssessment =>
      hasCloudSyncState || backupAccountIds.isNotEmpty;
}
