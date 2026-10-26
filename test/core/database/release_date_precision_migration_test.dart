// SN-49: migration 39 records how much of each release date is known.
// A real version 31 database is migrated to 38, given dates with known
// provenance, then upgraded by the app; every date value is kept.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/release_date_precision_backfill.dart';

final _v31Fixture = File(
  path.join('test', 'fixtures', 'recovery', 'sonus_v31.db'),
);

void main() {
  sqfliteFfiInit();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_release_dates_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const now = '2026-10-26T00:00:00.000Z';

  /// A version 38 database with three dated editions:
  /// - `edition-v31a`: a year read from a file tag (saved as local
  ///   midnight on January 1);
  /// - `edition-v31b`: a date someone typed;
  /// - `edition-tagged-midyear`: tag provenance but not at a year's start,
  ///   which no import produces, so it is left alone.
  Future<String> v38WithDates() async {
    final file = path.join(root.path, 'v38.db');
    await _v31Fixture.copy(file);
    final db = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 38,
        onUpgrade: (db, oldVersion, newVersion) => DatabaseMigrations.migrate(
          db,
          oldVersion: oldVersion,
          newVersion: newVersion,
        ),
      ),
    );
    try {
      final albumId =
          (await db.query(
                DatabaseTables.albumEditions,
                columns: ['album_id'],
                where: 'id = ?',
                whereArgs: ['edition-v31a'],
              )).single['album_id']!
              as String;
      await db.insert(DatabaseTables.albumEditions, {
        'id': 'edition-tagged-midyear',
        'album_id': albumId,
        'title': 'Live',
        'type': 'other',
        'is_primary': 0,
        'release_date': '2018-06-15T00:00:00.000Z',
        'created_at': now,
        'updated_at': now,
      });
      Future<void> date(String id, String value) => db.update(
        DatabaseTables.albumEditions,
        {'release_date': value},
        where: 'id = ?',
        whereArgs: [id],
      );
      await date('edition-v31a', '2019-01-01T05:00:00.000Z');
      await date('edition-v31b', '2021-06-04T00:00:00.000Z');

      Future<void> state(String id, String authority, String source) =>
          db.insert(DatabaseTables.metadataFieldStates, {
            'entity_type': 'albumEdition',
            'entity_id': id,
            'field_name': 'releaseDate',
            'authority': authority,
            'source': source,
            'updated_at': now,
          });
      await state('edition-v31a', 'imported', 'embeddedTag');
      await state('edition-v31b', 'manual', 'user');
      await state('edition-tagged-midyear', 'imported', 'embeddedTag');
    } finally {
      await db.close();
    }
    return file;
  }

  Future<Map<String, (String?, String?)>> dates(DatabaseExecutor db) async => {
    for (final row in await db.query(
      DatabaseTables.albumEditions,
      columns: ['id', 'release_date', 'release_date_precision'],
    ))
      row['id']! as String: (
        row['release_date'] as String?,
        row['release_date_precision'] as String?,
      ),
  };

  test('only dates read from file tags become year-only; no date '
      'changes', () async {
    final file = await v38WithDates();
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: file,
    );

    try {
      final db = await database.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        39,
      );
      expect(await dates(db), {
        'edition-v31a': ('2019-01-01T05:00:00.000Z', 'year'),
        'edition-v31b': ('2021-06-04T00:00:00.000Z', null),
        'edition-tagged-midyear': ('2018-06-15T00:00:00.000Z', null),
      });
    } finally {
      await database.close();
    }
  });

  test(
    'the backfill is safe to run again and keeps chosen precision',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: await v38WithDates(),
      );

      try {
        final db = await database.database;
        // A precision someone chose is never overwritten.
        await db.update(
          DatabaseTables.albumEditions,
          {'release_date_precision': 'day'},
          where: 'id = ?',
          whereArgs: ['edition-v31a'],
        );
        expect(await ReleaseDatePrecisionBackfill.run(db), 0);
        expect((await dates(db))['edition-v31a'], (
          '2019-01-01T05:00:00.000Z',
          'day',
        ));
      } finally {
        await database.close();
      }
    },
  );

  test('precision accepts only year, month or day', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: await v38WithDates(),
    );

    try {
      final db = await database.database;
      await expectLater(
        db.update(
          DatabaseTables.albumEditions,
          {'release_date_precision': 'week'},
          where: 'id = ?',
          whereArgs: ['edition-v31b'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await database.close();
    }
  });
}
