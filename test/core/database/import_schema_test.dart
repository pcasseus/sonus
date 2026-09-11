import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates import batch table with expected columns', () async {
    final db = await appDatabase.database;

    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.importBatches})',
    );

    final names = columns.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'id',
        'status',
        'total_count',
        'imported_count',
        'relinked_count',
        'skipped_count',
        'failed_count',
        'created_at',
        'started_at',
        'completed_at',
      }),
    );
  });

  test('accepts a valid pending import batch', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    await expectLater(
      db.insert(DatabaseTables.importBatches, {
        'id': 'batch_valid',
        'status': 'pending',
        'total_count': 3,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
        'started_at': null,
        'completed_at': null,
      }),
      completes,
    );
  });

  test('rejects unknown import batch status', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.importBatches, {
        'id': 'batch_invalid_status',
        'status': 'exploded',
        'total_count': 0,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects negative import batch counts', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.importBatches, {
        'id': 'batch_negative',
        'status': 'pending',
        'total_count': -1,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
