import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';

/// SN-45 migration 36: chart Moments accept the all-time scope.
void main() {
  sqfliteFfiInit();

  const table = DatabaseTables.chartMomentEvents;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_moment_scope_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Database> openAt(String file, int version) =>
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

  Map<String, Object?> moment(String id, String scope) => {
    'id': id,
    'deduplication_key': 'key-$id',
    'source_id': 'play-$id',
    'chart_type': 'songs',
    'scope': scope,
    'event_type': 'debut',
    'entity_id': 'song-1',
    'entity_title': 'Song',
    'entity_artist_name': 'Artist',
    'week_start_utc': '2026-10-18T04:00:00.000Z',
    'week_end_utc': '2026-10-25T04:00:00.000Z',
    'occurred_at': '2026-10-20T12:00:00.000Z',
    'created_at': '2026-10-20T12:00:00.000Z',
    'current_rank': 12,
  };

  Future<List<Map<String, Object?>>> indexes(Database db) => db.rawQuery(
    "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
    "AND tbl_name = ? ORDER BY name",
    [table],
  );

  test(
    'existing Moments, columns and indexes survive; allTime is accepted',
    () async {
      final file = path.join(root.path, 'moments.db');
      await File(
        path.join('test', 'fixtures', 'recovery', 'sonus_v31.db'),
      ).copy(file);

      final v35 = await openAt(file, 35);
      final List<Map<String, Object?>> rowsBefore;
      final List<Map<String, Object?>> columnsBefore;
      final List<Map<String, Object?>> indexesBefore;
      try {
        await v35.insert(table, moment('weekly', 'finalized'));
        await v35.insert(table, moment('live', 'live'));
        await expectLater(
          v35.insert(table, moment('early', 'allTime')),
          throwsA(isA<DatabaseException>()),
          reason: 'version 35 must not hold all-time Moments',
        );
        rowsBefore = await v35.query(table, orderBy: 'id');
        columnsBefore = await v35.rawQuery('PRAGMA table_info($table)');
        indexesBefore = await indexes(v35);
      } finally {
        await v35.close();
      }

      final v36 = await openAt(file, 36);
      try {
        expect(await v36.query(table, orderBy: 'id'), rowsBefore);
        expect(await v36.rawQuery('PRAGMA table_info($table)'), columnsBefore);
        expect(await indexes(v36), indexesBefore);

        await v36.insert(table, moment('all-time', 'allTime'));
        await expectLater(
          v36.insert(table, moment('bad', 'yearly')),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          v36.insert(table, {
            ...moment('dup', 'allTime'),
            'deduplication_key': 'key-all-time',
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'deduplication keys stay unique',
        );

        final leftovers = await v36.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE '%_rebuild'",
        );
        expect(leftovers, isEmpty);
      } finally {
        await v36.close();
      }
    },
  );
}
