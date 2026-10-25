import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

void main() {
  sqfliteFfiInit();

  test('every physical application table has a backup policy', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await appDatabase.database;

      final rows = await db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
      ''');

      final actual = rows.map((row) => row['name']! as String).toSet();

      final covered = BackupCoverageContract.tables
          .map((entry) => entry.table)
          .toSet();

      final missingPolicies = actual.difference(covered);
      final missingTables = covered.difference(actual);

      expect(
        missingPolicies,
        isEmpty,
        reason: 'Database tables have no backup classification.',
      );

      expect(
        missingTables,
        isEmpty,
        reason: 'Backup contract references nonexistent database tables.',
      );

      expect(actual, hasLength(32));
    } finally {
      await appDatabase.close();
    }
  });
}
