import 'package:sqflite/sqflite.dart';

import '../models/backup_data_payload.dart';
import '../models/backup_table_coverage.dart';

class BackupPayloadSchemaValidator {
  const BackupPayloadSchemaValidator();

  Future<void> validate({
    required DatabaseExecutor database,
    required BackupDataPayload payload,
  }) async {
    for (final coverage in BackupCoverageContract.portableTables) {
      final table = coverage.table;

      // Table names come exclusively from the trusted coverage contract.
      final schema = await database.rawQuery('PRAGMA table_info("$table")');

      if (schema.isEmpty) {
        throw FormatException('Missing database schema for $table.');
      }

      final expectedColumns = schema
          .map((column) => column['name'] as String)
          .toSet();

      final rows = payload.tables[table];

      if (rows == null) {
        throw FormatException('Missing portable table $table.');
      }

      for (var index = 0; index < rows.length; index++) {
        final actualColumns = rows[index].keys.toSet();

        if (actualColumns.length != expectedColumns.length ||
            !actualColumns.containsAll(expectedColumns)) {
          throw FormatException(
            'Invalid column structure in $table at row $index.',
          );
        }
      }
    }
  }
}
