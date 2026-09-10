import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';

void main() {
  sqfliteFfiInit();

  test('database reports the current Sonus schema version', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await appDatabase.database;

      final result = await db.rawQuery('PRAGMA user_version');

      expect(result.single['user_version'], AppDatabase.databaseVersion);

      expect(AppDatabase.databaseVersion, 1);
    } finally {
      await appDatabase.close();
    }
  });

  test('migration runner ignores same-version requests', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 1, newVersion: 1),
        completes,
      );
    } finally {
      await db.close();
    }
  });

  test('migration runner fails loudly for unknown future migration', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await expectLater(
        DatabaseMigrations.migrate(db, oldVersion: 1, newVersion: 2),
        throwsA(isA<UnsupportedError>()),
      );
    } finally {
      await db.close();
    }
  });
}
