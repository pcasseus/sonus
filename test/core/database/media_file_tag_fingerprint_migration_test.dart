// App Update 1.2, BUG-09 Refinement B: version 44 adds one nullable column,
// the tags' fingerprint, to the device-local file bindings; nothing else,
// and no existing row changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/data/mappers/media_file_binding_row_mapper.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

import '../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('sonus_v44_'));
  tearDown(() => dir.delete(recursive: true));

  Future<Set<String>> objectsOf(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT type || ':' || name AS o FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%'",
    ))
      row['o']! as String,
  };

  Future<Map<String, Map<String, Object?>>> columnsOf(
    Database db,
    String table,
  ) async => {
    for (final c in await db.rawQuery('PRAGMA table_info($table)'))
      c['name']! as String: {
        'type': c['type'],
        'notnull': c['notnull'],
        'pk': c['pk'],
      },
  };

  /// Today's fresh schema with [dropping] removed from the bindings and the
  /// tables and index of [withoutObjects] left out: an older database.
  Future<Database> olderDatabase(
    String file, {
    required int version,
    required List<RegExp> dropping,
    Set<String> withoutObjects = const {},
  }) async {
    final fresh = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(dir.path, 'reference_$version.db'),
    );
    final statements = [
      for (final row in await (await fresh.database).rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL "
        "AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name",
      ))
        (row['name']! as String, row['sql']! as String),
    ];
    await fresh.close();

    final db = await databaseFactoryFfi.openDatabase(file);
    for (final (name, sql) in statements) {
      if (withoutObjects.contains(name)) continue;
      var statement = sql;
      if (name == DatabaseTables.mediaFileBindings) {
        for (final column in dropping) {
          statement = statement.replaceFirst(column, '');
        }
      }
      await db.execute(statement);
    }
    await db.execute('PRAGMA user_version = $version');
    return db;
  }

  final v44Column = RegExp(r'tag_fingerprint TEXT,\s*');
  final v43Columns = [
    RegExp(r'audio_signature TEXT,\s*'),
    RegExp(r'audio_full_hash TEXT,\s*'),
    RegExp(
      r'signature_version INTEGER CHECK \(signature_version IS NULL '
      r'OR signature_version >= 1\),\s*',
    ),
  ];
  const v43Objects = {
    'deleted_audio_signatures',
    'idx_media_file_bindings_audio_signature',
  };

  Future<Database> version43(String file) =>
      olderDatabase(file, version: 43, dropping: [v44Column]);

  Future<Database> version42(String file) => olderDatabase(
    file,
    version: 42,
    dropping: [...v43Columns, v44Column],
    withoutObjects: v43Objects,
  );

  Future<void> seed(Database db) async {
    await seedConnectedLibrary(db, key: 'one');
    await seedMediaBinding(db, key: 'one');
  }

  Future<Database> freshDatabase() async => AppDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: path.join(dir.path, 'fresh.db'),
  ).database;

  test('a fresh database has the fingerprint column, empty', () async {
    final db = await freshDatabase();
    expect(
      (await db.rawQuery('PRAGMA user_version')).single['user_version'],
      45,
    );
    expect(
      (await columnsOf(
        db,
        DatabaseTables.mediaFileBindings,
      ))['tag_fingerprint'],
      {'type': 'TEXT', 'notnull': 0, 'pk': 0},
    );
    await seed(db);
    expect(
      (await db.query(
        DatabaseTables.mediaFileBindings,
      )).single['tag_fingerprint'],
      isNull,
    );
    await db.close();
  });

  test('43 to 44 adds only the column and keeps every row', () async {
    final db = await version43(path.join(dir.path, 'v43.db'));
    await seed(db);
    final before = await snapshotDatabase(db);
    final objectsBefore = await objectsOf(db);

    await DatabaseMigrations.migrate(db, oldVersion: 43, newVersion: 44);
    // Running it again (an interrupted upgrade) is harmless.
    await DatabaseMigrations.migrate(db, oldVersion: 43, newVersion: 44);

    final fresh = await freshDatabase();
    expect(await objectsOf(db), objectsBefore, reason: 'no new table or index');
    expect(
      await columnsOf(db, DatabaseTables.mediaFileBindings),
      await columnsOf(fresh, DatabaseTables.mediaFileBindings),
    );
    final after = await snapshotDatabase(db);
    expect(
      after[DatabaseTables.mediaFileBindings]!.single['tag_fingerprint'],
      isNull,
    );
    expect({
      ...after,
      DatabaseTables.mediaFileBindings: [
        for (final row in after[DatabaseTables.mediaFileBindings]!)
          {...row}..remove('tag_fingerprint'),
      ],
    }, before);
    expect(after[DatabaseTables.songs], hasLength(1), reason: 'no song lost');
    await fresh.close();
    await db.close();
  });

  test('42 to 43 to 44 equals a fresh database and keeps every row', () async {
    final file = path.join(dir.path, 'v42.db');
    final db = await version42(file);
    await seed(db);
    final songsBefore = await db.query(DatabaseTables.songs);
    await db.close();

    // Opening with the app runs 43, then 44.
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: file,
    );
    final opened = await app.database;
    addTearDown(app.close);
    final fresh = await freshDatabase();

    expect(
      (await opened.rawQuery('PRAGMA user_version')).single['user_version'],
      45,
    );
    expect(await objectsOf(opened), await objectsOf(fresh));
    expect(
      await columnsOf(opened, DatabaseTables.mediaFileBindings),
      await columnsOf(fresh, DatabaseTables.mediaFileBindings),
    );
    expect(await opened.query(DatabaseTables.songs), songsBefore);
    final binding = (await opened.query(
      DatabaseTables.mediaFileBindings,
    )).single;
    expect(binding['audio_signature'], isNull);
    expect(binding['tag_fingerprint'], isNull);
    await fresh.close();
  });

  test('a binding keeps its fingerprint through the mapper', () async {
    final db = await freshDatabase();
    await seed(db);
    final binding = MediaFileBindingRowMapper.fromRow(
      (await db.query(DatabaseTables.mediaFileBindings)).single,
    );
    expect(binding.tagFingerprint, isNull);
    await db.update(
      DatabaseTables.mediaFileBindings,
      MediaFileBindingRowMapper.toRow(
        binding.copyWith(tagFingerprint: 't1:abc:def'),
      ),
      where: 'id = ?',
      whereArgs: [binding.id],
    );
    expect(
      MediaFileBindingRowMapper.fromRow(
        (await db.query(DatabaseTables.mediaFileBindings)).single,
      ).tagFingerprint,
      't1:abc:def',
    );
    await db.close();
  });

  test('backups stay compatible: the bindings are device-local, and 44 is '
      'restorable like 43', () {
    expect(BackupCompatibility.restorableDatabaseVersions, contains(44));
    expect(BackupCompatibility.restorableDatabaseVersions, contains(43));
    final bindings = BackupCoverageContract.tables.singleWhere(
      (t) => t.table == DatabaseTables.mediaFileBindings,
    );
    expect(bindings.policy, BackupTablePolicy.deviceLocal);
  });
}
