import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await ChartSchema.create(db);
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates chart snapshot and entry tables', () async {
    final tables = await database.rawQuery(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (?, ?)
        ORDER BY name
      ''',
      [DatabaseTables.chartEntries, DatabaseTables.chartSnapshots],
    );

    expect(tables.map((row) => row['name']).toSet(), {
      DatabaseTables.chartEntries,
      DatabaseTables.chartSnapshots,
    });
  });

  test(
    'creates stable artist identity columns for charts and Moments',
    () async {
      final entryColumns = await database.rawQuery(
        'PRAGMA table_info(${DatabaseTables.chartEntries})',
      );

      expect(entryColumns.map((row) => row['name']), contains('artist_id'));

      final momentColumns = await database.rawQuery(
        'PRAGMA table_info(${DatabaseTables.chartMomentEvents})',
      );

      expect(
        momentColumns.map((row) => row['name']),
        containsAll({'entity_artist_id', 'related_entity_artist_id'}),
      );
    },
  );
  test('stores finalized historical chart identity independently', () async {
    const createdAt = '2026-10-04T04:00:00.000Z';

    await database.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-song-week-1',
      'chart_type': 'songs',
      'week_start_utc': '2026-09-27T04:00:00.000Z',
      'week_end_utc': '2026-10-04T04:00:00.000Z',
      'finalized_at': createdAt,
      'revision': 1,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    await database.insert(DatabaseTables.chartEntries, {
      'id': 'entry-song-week-1',
      'chart_snapshot_id': 'snapshot-song-week-1',
      'entity_id': 'deleted-song-id',
      'title': 'Historical Song',
      'artist_name': 'Historical Artist',
      'album_title': 'Historical Album',
      'rank': 4,
      'qualified_stream_count': 37,
      'previous_final_rank': 9,
      'peak_rank': 1,
      'peak_achieved_at': '2026-09-29T18:00:00.000Z',
      'weeks_on_chart': 3,
      'movement': 'up',
      'last_qualified_at': '2026-10-03T22:00:00.000Z',
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    final entries = await database.query(DatabaseTables.chartEntries);

    expect(entries, hasLength(1));
    expect(entries.single['entity_id'], 'deleted-song-id');
    expect(entries.single['title'], 'Historical Song');
    expect(entries.single['artist_name'], 'Historical Artist');
    expect(entries.single['album_title'], 'Historical Album');
    expect(entries.single['rank'], 4);
    expect(entries.single['peak_rank'], 1);
  });

  test('supports album chart snapshots', () async {
    const createdAt = '2026-10-04T04:00:00.000Z';

    await database.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-album-week-1',
      'chart_type': 'albums',
      'week_start_utc': '2026-09-27T04:00:00.000Z',
      'week_end_utc': '2026-10-04T04:00:00.000Z',
      'finalized_at': createdAt,
      'revision': 1,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    final rows = await database.query(DatabaseTables.chartSnapshots);

    expect(rows, hasLength(1));
    expect(rows.single['chart_type'], 'albums');
  });

  test('allows extended standings through rank 200', () async {
    const createdAt = '2026-10-04T04:00:00.000Z';

    await database.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-extended',
      'chart_type': 'songs',
      'week_start_utc': '2026-09-27T04:00:00.000Z',
      'week_end_utc': '2026-10-04T04:00:00.000Z',
      'finalized_at': createdAt,
      'revision': 1,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    await database.insert(DatabaseTables.chartEntries, {
      'id': 'entry-rank-200',
      'chart_snapshot_id': 'snapshot-extended',
      'entity_id': 'song-200',
      'title': 'Extended Song',
      'artist_name': 'Extended Artist',
      'album_title': 'Extended Album',
      'rank': 200,
      'qualified_stream_count': 1,
      'previous_final_rank': null,
      'peak_rank': 200,
      'peak_achieved_at': createdAt,
      'weeks_on_chart': 0,
      'movement': 'newEntry',
      'last_qualified_at': createdAt,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    final rows = await database.query(DatabaseTables.chartEntries);

    expect(rows.single['rank'], 200);
    expect(rows.single['weeks_on_chart'], 0);
  });

  test('rejects positions beyond extended standings limit', () async {
    const createdAt = '2026-10-04T04:00:00.000Z';

    await database.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-invalid-rank',
      'chart_type': 'songs',
      'week_start_utc': '2026-09-27T04:00:00.000Z',
      'week_end_utc': '2026-10-04T04:00:00.000Z',
      'finalized_at': createdAt,
      'revision': 1,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    await expectLater(
      database.insert(DatabaseTables.chartEntries, {
        'id': 'entry-rank-201',
        'chart_snapshot_id': 'snapshot-invalid-rank',
        'entity_id': 'song-201',
        'title': 'Invalid Song',
        'artist_name': 'Invalid Artist',
        'album_title': 'Invalid Album',
        'rank': 201,
        'qualified_stream_count': 1,
        'previous_final_rank': null,
        'peak_rank': 201,
        'peak_achieved_at': createdAt,
        'weeks_on_chart': 0,
        'movement': 'newEntry',
        'last_qualified_at': createdAt,
        'created_at': createdAt,
        'updated_at': createdAt,
      }),
      throwsA(anything),
    );
  });

  test('deleting snapshot cascades its historical entries', () async {
    const createdAt = '2026-10-04T04:00:00.000Z';

    await database.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-cascade',
      'chart_type': 'songs',
      'week_start_utc': '2026-09-27T04:00:00.000Z',
      'week_end_utc': '2026-10-04T04:00:00.000Z',
      'finalized_at': createdAt,
      'revision': 1,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    await database.insert(DatabaseTables.chartEntries, {
      'id': 'entry-cascade',
      'chart_snapshot_id': 'snapshot-cascade',
      'entity_id': 'song-cascade',
      'title': 'Cascade Song',
      'artist_name': 'Cascade Artist',
      'album_title': 'Cascade Album',
      'rank': 1,
      'qualified_stream_count': 10,
      'previous_final_rank': null,
      'peak_rank': 1,
      'peak_achieved_at': createdAt,
      'weeks_on_chart': 1,
      'movement': 'newEntry',
      'last_qualified_at': createdAt,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    await database.delete(
      DatabaseTables.chartSnapshots,
      where: 'id = ?',
      whereArgs: ['snapshot-cascade'],
    );

    final rows = await database.query(DatabaseTables.chartEntries);

    expect(rows, isEmpty);
  });

  test('creates chart query indexes', () async {
    final rows = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND (
            tbl_name = '${DatabaseTables.chartSnapshots}'
            OR tbl_name = '${DatabaseTables.chartEntries}'
          )
      ''');

    final names = rows.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'idx_chart_snapshots_week',
        'idx_chart_snapshots_type_week',
        'idx_chart_entries_snapshot_rank',
        'idx_chart_entries_entity',
      }),
    );
  });
}
