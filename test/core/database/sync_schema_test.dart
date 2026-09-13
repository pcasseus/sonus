import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await SyncSchema.create(db);
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates sync state and outbox tables', () async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN (?, ?)
      ORDER BY name
      ''',
      [DatabaseTables.syncState, DatabaseTables.syncOutbox],
    );

    expect(rows.map((row) => row['name']), [
      DatabaseTables.syncOutbox,
      DatabaseTables.syncState,
    ]);
  });

  test('rejects a half-populated server cursor', () async {
    expect(
      () => database.insert(DatabaseTables.syncState, {
        'user_id': 'user_1',
        'entity_type': 'artist',
        'last_server_updated_at': '2026-09-13T12:00:00.000Z',
        'last_server_id': null,
        'updated_at': '2026-09-13T12:00:00.000Z',
      }),
      throwsA(anything),
    );
  });

  test('allows an empty initial server cursor', () async {
    await database.insert(DatabaseTables.syncState, {
      'user_id': 'user_1',
      'entity_type': 'artist',
      'last_server_updated_at': null,
      'last_server_id': null,
      'updated_at': '2026-09-13T12:00:00.000Z',
    });

    final rows = await database.query(DatabaseTables.syncState);

    expect(rows, hasLength(1));
  });
}
