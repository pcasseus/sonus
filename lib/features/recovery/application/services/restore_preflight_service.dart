import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../models/backup_manifest.dart';
import '../models/backup_table_coverage.dart';
import '../models/restore_preflight.dart';
import 'backup_archive_verifier.dart';
import 'backup_payload_schema_validator.dart';
import 'storage_space_probe.dart';

/// Decides whether a verified backup may be restored onto this device.
///
/// Read-only: it never modifies the local database.
class RestorePreflightService {
  const RestorePreflightService({
    required this.appDatabase,
    this.schemaValidator = const BackupPayloadSchemaValidator(),
    this.storageProbe,
    this.storagePath,
  });

  final AppDatabase appDatabase;
  final BackupPayloadSchemaValidator schemaValidator;

  /// Free-space source; when null, free space is reported as unverified.
  final StorageSpaceProbe? storageProbe;

  /// A path on the volume that will hold restored data.
  final String? storagePath;

  /// Headroom beyond the estimate, for SQLite journaling and rounding.
  static const storageMarginBytes = 32 * 1024 * 1024;

  // Portable tables whose rows record the owning account.
  static const ownershipTables = [
    DatabaseTables.playbackSessions,
    DatabaseTables.qualifiedPlays,
    DatabaseTables.chartMomentEvents,
  ];

  static const _pendingSyncTables = [
    DatabaseTables.syncOutbox,
    SyncSchema.artistWriteJournalTable,
    SyncSchema.artistDependencyJournalTable,
  ];

  static const _cloudStateTables = [
    DatabaseTables.localAccountBinding,
    DatabaseTables.syncState,
    SyncSchema.cloudRevisionBaselinesTable,
  ];

  Future<RestorePreflight> assess(VerifiedBackupContents contents) async {
    final database = await appDatabase.database;

    final preflight = await database.transaction(
      (transaction) => assessWithin(transaction, contents),
    );

    return _withStorageCheck(preflight);
  }

  /// Evaluates every database-dependent blocker against [transaction].
  ///
  /// Read-only. Free space is not checked here; see [assess]. The restore
  /// orchestrator calls this again inside its restore transaction, where no
  /// other write can interleave, so the decision it acts on is never stale.
  Future<RestorePreflight> assessWithin(
    DatabaseExecutor transaction,
    VerifiedBackupContents contents,
  ) async {
    final backup = contents.backup;
    final manifest = backup.manifest;

    final blockers = <RestoreBlocker>[];

    if (manifest.formatVersion != BackupManifest.currentFormatVersion ||
        manifest.databaseVersion != AppDatabase.databaseVersion) {
      blockers.add(RestoreBlocker.incompatibleBackupVersion);
    }

    final versionRows = await transaction.rawQuery('PRAGMA user_version');
    final localVersion = versionRows.isEmpty
        ? null
        : versionRows.single['user_version'];

    if (localVersion != AppDatabase.databaseVersion) {
      blockers.add(RestoreBlocker.incompatibleLocalDatabase);
    } else if (!blockers.contains(
      RestoreBlocker.incompatibleBackupVersion,
    )) {
      try {
        await schemaValidator.validate(
          database: transaction,
          payload: backup.payload,
        );
      } on FormatException {
        blockers.add(RestoreBlocker.schemaMismatch);
      }
    }

    final backupAccounts = <String>{
      for (final table in ownershipTables)
        for (final row in backup.payload.tables[table] ?? const [])
          if (row['user_id'] case final String userId
              when userId.trim().isNotEmpty)
            userId,
    };

    final bindingRows = await transaction.query(
      DatabaseTables.localAccountBinding,
      columns: ['user_id'],
    );
    final localAccountId = bindingRows.isEmpty
        ? null
        : bindingRows.single['user_id'] as String?;

    if (backupAccounts.length > 1) {
      blockers.add(RestoreBlocker.multipleBackupAccounts);
    } else if (localAccountId != null &&
        backupAccounts.isNotEmpty &&
        !backupAccounts.contains(localAccountId)) {
      blockers.add(RestoreBlocker.accountConflict);
    }

    var pending = 0;
    for (final table in _pendingSyncTables) {
      pending += await _count(transaction, table);
    }

    // Pending cloud work is never discarded; it must sync first.
    if (pending > 0) {
      blockers.add(RestoreBlocker.pendingSyncWork);
    }

    var cloudStateRows = 0;
    for (final table in _cloudStateTables) {
      cloudStateRows += await _count(transaction, table);
    }

    return RestorePreflight(
      blockers: blockers,
      backupId: manifest.backupId,
      backupCreatedAtUtc: manifest.createdAtUtc,
      backupDatabaseVersion: manifest.databaseVersion,
      backupAccountIds: backupAccounts,
      localAccountId: localAccountId,
      pendingSyncItemCount: pending,
      hasCloudSyncState: cloudStateRows > 0,
      estimatedRequiredBytes:
          _estimateBytes(contents) +
          await _estimateSafetyBackupBytes(transaction),
    );
  }

  Future<RestorePreflight> _withStorageCheck(RestorePreflight preflight) async {
    final probe = storageProbe;
    final target = storagePath;

    if (probe == null || target == null) {
      return preflight;
    }

    final blockers = [...preflight.blockers];
    int? available;

    try {
      available = await probe.availableBytes(target);

      if (available != null &&
          available < preflight.estimatedRequiredBytes + storageMarginBytes) {
        blockers.add(RestoreBlocker.insufficientStorage);
      }
    } on StorageSpaceUnavailable {
      // The platform supports the query but it failed: fail closed.
      blockers.add(RestoreBlocker.storageCheckFailed);
    }

    return RestorePreflight(
      blockers: blockers,
      backupId: preflight.backupId,
      backupCreatedAtUtc: preflight.backupCreatedAtUtc,
      backupDatabaseVersion: preflight.backupDatabaseVersion,
      backupAccountIds: preflight.backupAccountIds,
      localAccountId: preflight.localAccountId,
      pendingSyncItemCount: preflight.pendingSyncItemCount,
      hasCloudSyncState: preflight.hasCloudSyncState,
      estimatedRequiredBytes: preflight.estimatedRequiredBytes,
      availableBytes: available,
    );
  }

  /// Space for the verified safety backup of the current library.
  Future<int> _estimateSafetyBackupBytes(DatabaseExecutor executor) async {
    var bytes = 0;

    final artwork = await executor.query(
      DatabaseTables.artworkAssets,
      columns: ['file_path'],
    );

    for (final row in artwork) {
      final file = File(row['file_path'] as String);

      if (await file.exists()) {
        bytes += await file.length();
      }
    }

    for (final coverage in BackupCoverageContract.portableTables) {
      for (final row in await executor.query(coverage.table)) {
        for (final value in row.values) {
          bytes += value is String ? value.length * 2 : 8;
        }
      }
    }

    // The archive is written once as a candidate and once while staging.
    return bytes * 2;
  }

  Future<int> _count(DatabaseExecutor executor, String table) async {
    // Table names come exclusively from the constants above.
    final rows = await executor.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
    return rows.single['c'] as int;
  }

  int _estimateBytes(VerifiedBackupContents contents) {
    var bytes = 0;

    for (final artwork in contents.artwork) {
      bytes += artwork.byteLength;
    }

    for (final rows in contents.backup.payload.tables.values) {
      for (final row in rows) {
        for (final value in row.values) {
          bytes += value is String ? value.length * 2 : 8;
        }
      }
    }

    return bytes;
  }
}
