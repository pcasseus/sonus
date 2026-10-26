import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';

/// SN-45 migration 35: the device-local crop table.
void main() {
  sqfliteFfiInit();

  const stamp = '2026-10-25T00:00:00.000Z';
  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
    for (final id in ['original', 'cropped']) {
      await db.insert(DatabaseTables.artworkAssets, {
        'id': id,
        'file_path': '/art/$id.png',
        'normalized_path': '/art/$id.png',
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  });

  tearDown(() => appDatabase.close());

  Map<String, Object?> row({
    String target = 'albumEdition',
    double left = 0.1,
    double top = 0,
    double width = 0.5,
    double height = 1,
  }) => {
    'target_type': target,
    'target_id': 'edition-1',
    'source_artwork_id': 'original',
    'output_artwork_id': 'cropped',
    'crop_left': left,
    'crop_top': top,
    'crop_width': width,
    'crop_height': height,
    'created_at': stamp,
    'updated_at': stamp,
  };

  test('fresh databases have the table', () async {
    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 37);
    await db.insert(DatabaseTables.artworkCrops, row());
    expect(await db.query(DatabaseTables.artworkCrops), hasLength(1));
  });

  test('rectangles outside the image are refused', () async {
    for (final bad in [
      row(left: -0.1),
      row(left: 0.6, width: 0.5),
      row(width: 0),
      row(top: 0.5, height: 0.6),
      row(target: 'song'),
    ]) {
      await expectLater(
        db.insert(DatabaseTables.artworkCrops, bad),
        throwsA(isA<DatabaseException>()),
        reason: '$bad',
      );
    }
  });

  test('one crop per target', () async {
    await db.insert(DatabaseTables.artworkCrops, row());
    await expectLater(
      db.insert(DatabaseTables.artworkCrops, row(left: 0.2)),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a crop goes away with its artwork asset', () async {
    await db.insert(DatabaseTables.artworkCrops, row());
    await db.delete(
      DatabaseTables.artworkAssets,
      where: 'id = ?',
      whereArgs: ['original'],
    );
    expect(await db.query(DatabaseTables.artworkCrops), isEmpty);
  });

  test('migration 35 only adds the empty table', () async {
    final raw = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await raw.execute('PRAGMA foreign_keys = ON');
      await raw.execute('''
        CREATE TABLE ${DatabaseTables.artworkAssets} (
          id TEXT PRIMARY KEY NOT NULL,
          file_path TEXT NOT NULL,
          normalized_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await DatabaseMigrations.migrate(raw, oldVersion: 34, newVersion: 35);

      final tables = await raw.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((t) => t['name']),
        contains(DatabaseTables.artworkCrops),
      );
      expect(await raw.query(DatabaseTables.artworkCrops), isEmpty);
    } finally {
      await raw.close();
    }
  });
}
