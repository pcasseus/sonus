// App Update 1.3 (user decision 2026-11-16): version 48 adds the
// published new-release debut stories, one row per song. Version 48 was
// never released, so the table joins the lyrics provenance in migration
// 48; a fresh install and an upgrade from 47 must be identical.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/lyrics_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

const _table = DatabaseTables.newReleaseDebutPublications;

Future<Database> _open() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    singleInstance: false,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  ),
);

/// The parts of version 47 migration 48 touches.
Future<Database> _version47({bool lyrics = true}) async {
  final db = await _open();
  await db.execute(
    'CREATE TABLE ${DatabaseTables.songs} (id TEXT PRIMARY KEY NOT NULL)',
  );
  if (lyrics) await LyricsSchema.create(db);
  return db;
}

Future<List<Map<String, Object?>>> _columns(DatabaseExecutor db) =>
    db.rawQuery('PRAGMA table_info($_table)');

Future<List<Map<String, Object?>>> _indexes(DatabaseExecutor db) =>
    db.rawQuery('PRAGMA index_list($_table)');

Future<String?> _sql(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
    [_table],
  );
  return rows.isEmpty ? null : rows.single['sql'] as String?;
}

void main() {
  sqfliteFfiInit();

  test('a fresh version 48 database has the table, keyed uniquely by '
      'song id, with no foreign keys', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      final db = await app.database;
      expect(AppDatabase.databaseVersion, 48);
      final columns = {for (final c in await _columns(db)) c['name']: c};
      expect(columns.keys, [
        'song_id',
        'story_id',
        'event_id',
        'event_deduplication_key',
        'kind',
        'chart_scope',
        'chart_rank',
        'chart_name',
        'week_start_utc',
        'debuted_at_utc',
        'song_title',
        'artist_name',
        'featured_artists',
        'album_id',
        'album_title',
        'album_format',
        'release_date',
        'release_date_precision',
        'headline',
        'published_at',
        'revision',
        'corrected_at',
      ]);
      expect(columns['song_id']!['pk'], 1);
      // The song id is the unique index.
      final unique = [
        for (final index in await _indexes(db))
          if (index['unique'] == 1) index['name'],
      ];
      expect(unique, hasLength(1));
      final indexed = await db.rawQuery('PRAGMA index_info(${unique.single})');
      expect(indexed.single['name'], 'song_id');
      // Published history is never cascaded away with a song row.
      expect(await db.rawQuery('PRAGMA foreign_key_list($_table)'), isEmpty);
      expect(await db.query(_table), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('47 to 48 adds the same table, empty; running it again changes '
      'nothing', () async {
    final upgraded = await _version47();
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      expect(await _sql(upgraded), isNull);
      await DatabaseMigrations.migrate(
        upgraded,
        oldVersion: 47,
        newVersion: 48,
      );
      final fresh = await app.database;

      expect(await _sql(upgraded), await _sql(fresh));
      expect(await _columns(upgraded), await _columns(fresh));
      expect(await _indexes(upgraded), await _indexes(fresh));
      expect(await upgraded.query(_table), isEmpty);

      await DatabaseMigrations.migrate(
        upgraded,
        oldVersion: 47,
        newVersion: 48,
      );
      expect(await _sql(upgraded), await _sql(fresh));
      expect(
        (await upgraded.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    } finally {
      await upgraded.close();
      await app.close();
    }
  });

  test(
    'the table is added even where version 47 had no lyrics table',
    () async {
      final upgraded = await _version47(lyrics: false);
      try {
        await DatabaseMigrations.migrate(
          upgraded,
          oldVersion: 47,
          newVersion: 48,
        );
        expect(await _sql(upgraded), isNotNull);
      } finally {
        await upgraded.close();
      }
    },
  );

  test('backed up as an optional portable table (older backups lack it)', () {
    final coverage = BackupCoverageContract.tables.singleWhere(
      (entry) => entry.table == _table,
    );
    expect(coverage.policy, BackupTablePolicy.portableData);
    expect(coverage.requiredInEveryBackup, isFalse);
  });
}
