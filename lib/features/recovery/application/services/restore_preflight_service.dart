import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../models/backup_manifest.dart';
import '../models/restore_preflight.dart';
import 'backup_archive_verifier.dart';
import 'backup_payload_schema_validator.dart';

/// Decides whether a verified backup may be restored onto this device.
///
/// Read-only: it never modifies the local database.
class RestorePreflightService {
  const RestorePreflightService({
    required this.appDatabase,
    this.schemaValidator = const BackupPayloadSchemaValidator(),
  });

  final AppDatabase appDatabase;
  final BackupPayloadSchemaValidator schemaValidator;

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
    final backup = contents.backup;
    final manifest = backup.manifest;
    final database = await appDatabase.database;

    return database.transaction((transaction) async {
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
        estimatedRequiredBytes: _estimateBytes(contents),
      );
    });
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
