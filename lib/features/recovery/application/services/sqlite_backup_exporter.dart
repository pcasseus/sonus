import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../models/backup_data_payload.dart';
import '../models/backup_manifest.dart';
import '../models/backup_table_coverage.dart';
import 'backup_payload_schema_validator.dart';

class SqliteBackupExporter {
  SqliteBackupExporter({
    required this.appDatabase,
    DateTime Function()? now,
    String Function()? generateId,
    this.schemaValidator = const BackupPayloadSchemaValidator(),
    this.afterTableRead,
  }) : _now = now ?? DateTime.now,
       _generateId = generateId ?? const Uuid().v4;

  final AppDatabase appDatabase;
  final DateTime Function() _now;
  final String Function() _generateId;
  final BackupPayloadSchemaValidator schemaValidator;
  final Future<void> Function(String table)? afterTableRead;

  Future<SqliteBackupExportResult> export() async {
    final database = await appDatabase.database;

    return database.transaction((transaction) async {
      final versionRows = await transaction.rawQuery('PRAGMA user_version');

      if (versionRows.length != 1 ||
          versionRows.single['user_version'] is! int ||
          versionRows.single['user_version'] != AppDatabase.databaseVersion) {
        throw FormatException(
          'Source database schema version does not match Sonus.',
        );
      }
      final tables = <String, List<Map<String, Object?>>>{};

      for (final coverage in BackupCoverageContract.portableTables) {
        final table = coverage.table;

        // Table identifiers originate from the trusted coverage contract.
        final rows = await transaction.query(table);

        tables[table] = [
          for (final row in rows) Map<String, Object?>.from(row),
        ];

        if (afterTableRead != null) {
          await afterTableRead!(table);
        }
      }

      final payload = BackupDataPayload(tables: tables);

      await schemaValidator.validate(database: transaction, payload: payload);

      final manifest = BackupManifest(
        backupId: _generateId(),
        createdAtUtc: _now().toUtc(),
        databaseVersion: AppDatabase.databaseVersion,
        rowCounts: {
          for (final entry in payload.tables.entries)
            entry.key: entry.value.length,
        },
      );

      payload.validateAgainst(manifest);

      return SqliteBackupExportResult(manifest: manifest, payload: payload);
    });
  }
}

class SqliteBackupExportResult {
  const SqliteBackupExportResult({
    required this.manifest,
    required this.payload,
  });

  final BackupManifest manifest;
  final BackupDataPayload payload;
}
