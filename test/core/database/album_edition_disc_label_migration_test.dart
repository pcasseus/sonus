// App Update 1.2, REF-13c: version 45 adds one table of optional disc
// names; nothing else, and no existing row changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

import '../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  final opened = <AppDatabase>[];
  setUp(() async => dir = await Directory.systemTemp.createTemp('sonus_v45_'));
  tearDown(() async {
    for (final database in opened) {
      await database.close();
    }
    opened.clear();
    await dir.delete(recursive: true);
  });

  const table = DatabaseTables.albumEditionDiscLabels;

  Future<AppDatabase> fresh(String name) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, name),
    );
    await database.database;
    opened.add(database);
    return database;
  }

  /// A version 44 database: today's schema without the disc names table,
  /// holding a real library.
  Future<Database> version44(String name) async {
    final database = await fresh(name);
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a');
    await seedConnectedLibrary(db, key: 'b', week: 1);
    await db.execute('DROP TABLE $table');
    await db.execute('PRAGMA user_version = 44');
    await database.close();
    return databaseFactoryFfi.openDatabase(path.join(dir.path, name));
  }

  Map<String, Object?> label(String edition, int disc, String text) => {
    'album_edition_id': edition,
    'disc_number': disc,
    'label': text,
    'created_at': '2026-11-12T00:00:00.000Z',
    'updated_at': '2026-11-12T00:00:00.000Z',
  };

  test('a fresh database has the table, empty, at version 45', () async {
    final db = await (await fresh('fresh.db')).database;
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      45,
    );
    expect(await db.query(table), isEmpty);
    expect(
      [
        for (final c in await db.rawQuery('PRAGMA table_info($table)'))
          c['name'],
      ],
      ['album_edition_id', 'disc_number', 'label', 'created_at', 'updated_at'],
    );
  });

  test('44 to 45 adds only the table and keeps every row', () async {
    final db = await version44('upgrade.db');
    final before = await snapshotDatabase(db);
    expect(before.containsKey(table), isFalse);

    await DatabaseMigrations.migrate(db, oldVersion: 44, newVersion: 45);
    // Running it again changes nothing.
    await DatabaseMigrations.migrate(db, oldVersion: 44, newVersion: 45);

    final after = await snapshotDatabase(db);
    expect(after[table], isEmpty);
    expect(after..remove(table), before);
    await db.close();
  });

  test('an upgraded version 45 has the same table as a fresh one', () async {
    final upgraded = await version44('upgraded.db');
    await DatabaseMigrations.migrate(upgraded, oldVersion: 44, newVersion: 45);
    final reference = await (await fresh('reference.db')).database;

    Future<Object?> sqlOf(Database db) async => (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = ?",
      [table],
    )).single['sql'];

    expect(await sqlOf(upgraded), await sqlOf(reference));
    await upgraded.close();
  });

  test('one name per edition and disc; never blank or before disc 1', () async {
    final db = await (await fresh('rules.db')).database;
    await seedConnectedLibrary(db, key: 'a');
    await db.insert(table, label('edition-a', 2, 'Bonus Tracks'));

    for (final invalid in [
      label('edition-a', 2, 'Again'),
      label('edition-a', 0, 'Zero'),
      label('edition-a', 3, '   '),
      label('no-such-edition', 1, 'Orphan'),
    ]) {
      await expectLater(db.insert(table, invalid), throwsA(anything));
    }
    expect(await db.query(table), hasLength(1));
  });

  test("an edition's names go with it", () async {
    final db = await (await fresh('cascade.db')).database;
    await seedConnectedLibrary(db, key: 'a');
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition-a-deluxe',
      'album_id': 'album-a',
      'title': 'Deluxe',
      'type': 'deluxe',
      'is_primary': 0,
      'created_at': '2026-11-12T00:00:00.000Z',
      'updated_at': '2026-11-12T00:00:00.000Z',
    });
    await db.insert(table, label('edition-a-deluxe', 1, 'Standard Album'));
    await db.insert(table, label('edition-a-deluxe', 2, 'Bonus Tracks'));
    await db.insert(table, label('edition-a', 2, 'Kept'));

    await db.delete(
      DatabaseTables.albumEditions,
      where: 'id = ?',
      whereArgs: ['edition-a-deluxe'],
    );

    final left = await db.query(table);
    expect(left.single['album_edition_id'], 'edition-a');
  });

  test('portable in backups; older backups without it still restore', () {
    final coverage = BackupCoverageContract.tables.singleWhere(
      (entry) => entry.table == table,
    );
    expect(coverage.isPortable, isTrue);
    expect(coverage.requiredInEveryBackup, isFalse);
    expect(BackupCompatibility.restorableDatabaseVersions, contains(44));
    expect(BackupCompatibility.restorableDatabaseVersions, contains(45));
  });
}
