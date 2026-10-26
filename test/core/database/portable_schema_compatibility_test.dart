import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

/// A real database written by the SN-42 release (database version 31).
final _v31Fixture = File(
  path.join('test', 'fixtures', 'recovery', 'sonus_v31.db'),
);

void main() {
  sqfliteFfiInit();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_portable_schema_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  /// A private copy, so the committed fixture is never migrated.
  Future<String> copyOfV31(String name) async {
    final copy = path.join(root.path, name);
    await _v31Fixture.copy(copy);
    return copy;
  }

  Future<Database> openWithoutMigrating(String file) => databaseFactoryFfi
      .openDatabase(file, options: OpenDatabaseOptions(readOnly: true));

  /// Opens [file] and runs the real migrations up to [version].
  Future<Database> migrateTo(String file, int version) =>
      databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: version,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
            db,
            oldVersion: oldVersion,
            newVersion: newVersion,
          ),
        ),
      );

  Future<int> userVersion(DatabaseExecutor db) async =>
      (await db.rawQuery('PRAGMA user_version')).single['user_version']! as int;

  Future<Set<String>> tableNames(DatabaseExecutor db) async => {
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    ))
      row['name']! as String,
  };

  test('only versions proven by this file are restorable', () {
    // Adding a version requires extending the migration proof below.
    expect(BackupCompatibility.restorableDatabaseVersions, {
      31,
      32,
      33,
      34,
      35,
      36,
    });
    expect(AppDatabase.databaseVersion, 36);
  });

  test('the fixture is a real version 31 database', () async {
    final db = await openWithoutMigrating(await copyOfV31('v31.db'));

    try {
      expect(await userVersion(db), 31);
      final tables = await tableNames(db);
      expect(tables, contains(SyncSchema.artistDependencyJournalTable));
      expect(tables, isNot(contains(SyncSchema.inboundDeferredRecordsTable)));
      expect(tables, isNot(contains(SyncSchema.outboundConflictsTable)));
    } finally {
      await db.close();
    }
  });

  test('portable tables are identical at every supported version', () async {
    final v31 = await openWithoutMigrating(await copyOfV31('v31.db'));
    final v32 = await migrateTo(await copyOfV31('v32.db'), 32);
    final v33 = await migrateTo(await copyOfV31('v33.db'), 33);
    final v34 = await migrateTo(await copyOfV31('v34.db'), 34);
    final v35 = await migrateTo(await copyOfV31('v35.db'), 35);
    final v36 = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: await copyOfV31('v36.db'),
    );
    final fresh = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(root.path, 'fresh.db'),
    );

    try {
      final reference = await _portableSchema(await fresh.database);

      expect(await userVersion(v32), 32);
      expect(await userVersion(v33), 33);
      expect(await userVersion(v34), 34);
      expect(await userVersion(v35), 35);
      expect(await userVersion(await v36.database), 36);
      // Required tables are identical everywhere; an optional table is
      // identical wherever the version has it.
      void expectCompatible(Map<String, Object> schema) {
        expect(
          schema.keys,
          containsAll(BackupCoverageContract.requiredPortableTableNames),
        );
        expect(schema, {for (final t in schema.keys) t: reference[t]});
      }

      expectCompatible(await _portableSchema(v31));
      expectCompatible(await _portableSchema(v32));
      expectCompatible(await _portableSchema(v33));
      expectCompatible(await _portableSchema(v34));
      expectCompatible(await _portableSchema(v35));
      expect(await _portableSchema(await v36.database), reference);
    } finally {
      await v31.close();
      await v32.close();
      await v33.close();
      await v34.close();
      await v35.close();
      await v36.close();
      await fresh.close();
    }
  });

  test('migrating version 31 keeps every row and adds empty ledgers', () async {
    final file = await copyOfV31('upgrade.db');

    final before = await openWithoutMigrating(file);
    final Map<String, List<Map<String, Object?>>> rowsBefore;
    try {
      rowsBefore = await _allRows(before);
    } finally {
      await before.close();
    }

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: file,
    );

    try {
      final db = await upgraded.database;
      final rowsAfter = await _allRows(db);

      expect(await userVersion(db), 36);
      expect(
        rowsAfter[DatabaseTables.artworkCrops],
        isEmpty,
        reason: 'migration 35 must not invent crops',
      );
      expect(
        rowsAfter[DatabaseTables.albumReleaseClassifications],
        isEmpty,
        reason: 'migration 34 must not classify anything by itself',
      );
      expect(rowsAfter[DatabaseTables.artistProjectAssignments], isEmpty);
      expect(
        rowsAfter[SyncSchema.inboundDeferredRecordsTable],
        isEmpty,
        reason: 'migration 32 must not invent replay obligations',
      );
      expect(rowsAfter[SyncSchema.outboundConflictsTable], isEmpty);
      rowsAfter
        ..remove(SyncSchema.inboundDeferredRecordsTable)
        ..remove(SyncSchema.outboundConflictsTable)
        ..remove(DatabaseTables.albumReleaseClassifications)
        ..remove(DatabaseTables.artistProjectAssignments)
        ..remove(DatabaseTables.artworkCrops);
      expect(rowsAfter, rowsBefore);

      // The fixture carries real library, ownership, and sync rows.
      expect(rowsBefore[DatabaseTables.songs], hasLength(2));
      expect(rowsBefore[DatabaseTables.localAccountBinding], hasLength(1));
      expect(rowsBefore[SyncSchema.cloudRevisionBaselinesTable], hasLength(1));
      expect(rowsBefore[DatabaseTables.mediaFileBindings], hasLength(1));

      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
    } finally {
      await upgraded.close();
    }
  });
}

/// Columns, foreign keys, and indexes of every portable table.
Future<Map<String, Object>> _portableSchema(DatabaseExecutor db) async {
  final schema = <String, Object>{};

  for (final coverage in BackupCoverageContract.portableTables) {
    // Table names come from the backup coverage contract.
    final table = coverage.table;
    final columns = await db.rawQuery('PRAGMA table_info("$table")');

    // Optional portable tables may predate this version.
    if (columns.isEmpty && !coverage.requiredInEveryBackup) continue;

    final indexes = <Object>[];

    for (final index in await db.rawQuery('PRAGMA index_list("$table")')) {
      indexes.add({
        'name': index['name'],
        'unique': index['unique'],
        'origin': index['origin'],
        'partial': index['partial'],
        'columns': await db.rawQuery('PRAGMA index_info("${index['name']}")'),
      });
    }

    indexes.sort((a, b) => '$a'.compareTo('$b'));

    schema[table] = {
      'columns': columns,
      'foreignKeys': await db.rawQuery('PRAGMA foreign_key_list("$table")'),
      'indexes': indexes,
    };
  }

  return schema;
}

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  DatabaseExecutor db,
) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );

  return {
    for (final row in tables)
      row['name']! as String: await db.rawQuery(
        'SELECT * FROM "${row['name']}" ORDER BY rowid',
      ),
  };
}
