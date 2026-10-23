import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_payload_schema_validator.dart';

Map<String, List<Map<String, Object?>>> emptyTables() => {
  for (final entry in BackupCoverageContract.portableTables)
    entry.table: <Map<String, Object?>>[],
};

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

  test('accepts complete empty portable payload', () async {
    final db = await appDatabase.database;
    final payload = BackupDataPayload(tables: emptyTables());

    await const BackupPayloadSchemaValidator().validate(
      database: db,
      payload: payload,
    );
  });

  test('rejects invented columns', () async {
    final db = await appDatabase.database;
    final tables = emptyTables();

    tables[DatabaseTables.artists] = [
      {'id': 'artist-1', 'invented_column': 'value'},
    ];

    final payload = BackupDataPayload(tables: tables);

    await expectLater(
      const BackupPayloadSchemaValidator().validate(
        database: db,
        payload: payload,
      ),
      throwsFormatException,
    );
  });

  test('rejects incomplete rows', () async {
    final db = await appDatabase.database;
    final tables = emptyTables();

    tables[DatabaseTables.artists] = [
      {'id': 'artist-1'},
    ];

    final payload = BackupDataPayload(tables: tables);

    await expectLater(
      const BackupPayloadSchemaValidator().validate(
        database: db,
        payload: payload,
      ),
      throwsFormatException,
    );
  });

  test('accepts actual SQLite rows without modifying them', () async {
    final db = await appDatabase.database;

    await db.insert(DatabaseTables.artists, {
      'id': 'artist-1',
      'name': 'Test Artist',
      'canonical_name': 'test artist',
      'created_at': '2026-10-21T00:00:00.000Z',
      'updated_at': '2026-10-21T00:00:00.000Z',
    });

    final tables = emptyTables();

    tables[DatabaseTables.artists] = [
      for (final row in await db.query(DatabaseTables.artists))
        Map<String, Object?>.from(row),
    ];

    final payload = BackupDataPayload(tables: tables);

    await const BackupPayloadSchemaValidator().validate(
      database: db,
      payload: payload,
    );

    expect(payload.tables[DatabaseTables.artists]!.single['id'], 'artist-1');
  });
}
