// App Update 1.2, REF-19: version 46 records where each finalized chart week
// came from (chart_snapshots.provenance) and when this database's chart
// history began (chart_history_origin). Every stored week is kept and left
// unknown; nothing is assumed to be original.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

/// chart_snapshots and chart_entries as version 45 created them.
Future<Database> _version45(String name) async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE ${DatabaseTables.chartSnapshots} (
      id TEXT PRIMARY KEY NOT NULL,
      chart_type TEXT NOT NULL CHECK (chart_type IN ('songs', 'albums')),
      week_start_utc TEXT NOT NULL,
      week_end_utc TEXT NOT NULL,
      finalized_at TEXT,
      revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(chart_type, week_start_utc),
      CHECK (week_end_utc > week_start_utc)
    )
  ''');
  await db.insert(DatabaseTables.chartSnapshots, {
    'id': 'week-1',
    'chart_type': 'songs',
    'week_start_utc': '2026-11-01T04:00:00.000Z',
    'week_end_utc': '2026-11-08T05:00:00.000Z',
    'finalized_at': '2026-11-08T05:00:00.000Z',
    'revision': 1,
    'created_at': '2026-11-08T05:00:00.000Z',
    'updated_at': '2026-11-08T05:00:00.000Z',
  });
  return db;
}

Future<List<Map<String, Object?>>> _columns(Database db) =>
    db.rawQuery('PRAGMA table_info(${DatabaseTables.chartSnapshots})');

void main() {
  sqfliteFfiInit();

  test('a fresh database records provenance and starts its history', () async {
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      final db = await app.database;
      expect(AppDatabase.databaseVersion, 46);
      final provenance = (await _columns(
        db,
      )).singleWhere((c) => c['name'] == 'provenance');
      expect(provenance['notnull'], 0);
      expect(provenance['dflt_value'], isNull);

      final origin = await db.query(DatabaseTables.chartHistoryOrigin);
      expect(origin, hasLength(1));
      expect(
        DateTime.parse(origin.single['origin_utc']! as String).isAfter(before),
        isTrue,
      );
    } finally {
      await app.close();
    }
  });

  test('45 to 46 keeps every week, unknown, and starts the history', () async {
    final db = await _version45('upgrade');
    try {
      final rowBefore = (await db.query(DatabaseTables.chartSnapshots)).single;

      await DatabaseMigrations.migrate(db, oldVersion: 45, newVersion: 46);

      final rowAfter = (await db.query(DatabaseTables.chartSnapshots)).single;
      expect(rowAfter['provenance'], isNull, reason: 'never assumed original');
      expect({...rowAfter}..remove('provenance'), rowBefore);
      final origin = await db.query(DatabaseTables.chartHistoryOrigin);
      expect(origin, hasLength(1));

      // Running it again changes nothing, the origin included.
      await DatabaseMigrations.migrate(db, oldVersion: 45, newVersion: 46);
      expect(await db.query(DatabaseTables.chartHistoryOrigin), origin);
      expect((await db.query(DatabaseTables.chartSnapshots)).single, rowAfter);
    } finally {
      await db.close();
    }
  });

  test('an upgraded week table matches a fresh one', () async {
    final upgraded = await _version45('compare');
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      await DatabaseMigrations.migrate(
        upgraded,
        oldVersion: 45,
        newVersion: 46,
      );
      expect(await _columns(upgraded), await _columns(await app.database));
    } finally {
      await upgraded.close();
      await app.close();
    }
  });

  test('provenance is original, unverified or unknown, nothing else', () async {
    final db = await _version45('check');
    try {
      await DatabaseMigrations.migrate(db, oldVersion: 45, newVersion: 46);
      for (final value in ['original', 'unverified', null]) {
        await db.update(DatabaseTables.chartSnapshots, {'provenance': value});
      }
      await expectLater(
        db.update(DatabaseTables.chartSnapshots, {'provenance': 'trusted'}),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });

  test('resetting the origin moves it, keeping one row', () async {
    final db = await _version45('reset');
    try {
      await DatabaseMigrations.migrate(db, oldVersion: 45, newVersion: 46);
      final restoredAt = DateTime.utc(2030, 1, 2, 3);
      await ChartSchema.resetChartHistoryOrigin(db, restoredAt);
      expect(await db.query(DatabaseTables.chartHistoryOrigin), [
        {'id': 1, 'origin_utc': restoredAt.toIso8601String()},
      ]);
    } finally {
      await db.close();
    }
  });

  test('backups carry provenance; the origin is never restored', () {
    final weeks = BackupCoverageContract.tables.singleWhere(
      (c) => c.table == DatabaseTables.chartSnapshots,
    );
    expect(weeks.isPortable, isTrue);
    expect(weeks.columnsAddedLater, contains('provenance'));
    final origin = BackupCoverageContract.tables.singleWhere(
      (c) => c.table == DatabaseTables.chartHistoryOrigin,
    );
    expect(origin.policy, BackupTablePolicy.internalState);
  });
}
