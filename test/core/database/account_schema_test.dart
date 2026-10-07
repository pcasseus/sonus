import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/account_schema.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await AccountSchema.create(db);
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates local account binding table', () async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = ?
      ''',
      [DatabaseTables.localAccountBinding],
    );

    expect(rows, hasLength(1));
    expect(rows.single['name'], DatabaseTables.localAccountBinding);
  });

  test('enforces a single local account binding row', () async {
    await database.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': 'user_1',
      'bound_at': '2026-10-06T12:00:00.000Z',
      'updated_at': '2026-10-06T12:00:00.000Z',
    });

    expect(
      () => database.insert(DatabaseTables.localAccountBinding, {
        'id': 2,
        'user_id': 'user_2',
        'bound_at': '2026-10-06T12:00:00.000Z',
        'updated_at': '2026-10-06T12:00:00.000Z',
      }),
      throwsA(anything),
    );
  });

  test('requires a non-null user id', () async {
    expect(
      () => database.insert(DatabaseTables.localAccountBinding, {
        'id': 1,
        'user_id': null,
        'bound_at': '2026-10-06T12:00:00.000Z',
        'updated_at': '2026-10-06T12:00:00.000Z',
      }),
      throwsA(anything),
    );
  });
}
