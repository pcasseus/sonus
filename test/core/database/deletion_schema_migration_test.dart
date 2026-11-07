// App Update 1.2: version 42 adds the deletion ledger and journal, and
// nothing else.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';

void main() {
  sqfliteFfiInit();

  Future<Map<String, String>> rawSchemaOf(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name']! as String: row['sql']! as String,
  };

  Future<Map<String, String>> schemaOf(Database db) async => {
    for (final MapEntry(:key, :value) in (await rawSchemaOf(db)).entries)
      key: value.replaceAll(RegExp(r'\s+'), ' '),
  };

  test('an upgraded version 42 equals a fresh one, table for table', () async {
    final dir = await Directory.systemTemp.createTemp('sonus_v42_');
    addTearDown(() => dir.delete(recursive: true));
    final fresh = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, 'fresh.db'),
    );
    final freshDb = await fresh.database;
    final freshSchema = await schemaOf(freshDb);
    final freshSql = await rawSchemaOf(freshDb);

    // A version 41 database: the fresh one without the two new tables.
    final upgraded = await databaseFactoryFfi.openDatabase(
      path.join(dir.path, 'v41.db'),
    );
    for (final MapEntry(key: name, value: sql) in freshSql.entries) {
      if (name.contains('deletion')) continue;
      if (sql.startsWith('CREATE TABLE')) await upgraded.execute(sql);
    }
    for (final MapEntry(key: name, value: sql) in freshSql.entries) {
      if (name.contains('deletion')) continue;
      if (!sql.startsWith('CREATE TABLE')) await upgraded.execute(sql);
    }
    final before = await schemaOf(upgraded);

    await DatabaseMigrations.migrate(upgraded, oldVersion: 41, newVersion: 42);
    // Running it again (an interrupted upgrade) is harmless.
    await DatabaseMigrations.migrate(upgraded, oldVersion: 41, newVersion: 42);

    final after = await schemaOf(upgraded);
    expect(after, freshSchema);
    expect(after.keys.toSet().difference(before.keys.toSet()), {
      DatabaseTables.libraryDeletionLedger,
      DatabaseTables.libraryDeletionJournal,
      'idx_library_deletion_journal_committed',
    });
    await upgraded.close();
    await fresh.close();
  });

  test('the ledger accepts only known kinds and reasons', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await app.database;
    Future<void> insert(String type, String reason) =>
        db.insert(DatabaseTables.libraryDeletionLedger, {
          'entity_type': type,
          'entity_id': 'id_$type',
          'reason': reason,
          'operation_id': 'op',
          'recorded_at': '2026-11-07T00:00:00Z',
        });

    await insert('song', 'userDeletion');
    await insert('mediaFile', 'userDeletion');
    await insert('album', 'duplicateMerge');
    await expectLater(insert('playlist', 'userDeletion'), throwsA(anything));
    await expectLater(insert('artist', 'hidden'), throwsA(anything));
    await expectLater(insert('song', 'userDeletion'), throwsA(anything));
    await app.close();
  });
}
