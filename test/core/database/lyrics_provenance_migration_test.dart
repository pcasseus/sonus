// App Update 1.3: version 48 records where each lyrics text came from.
// Every stored text is kept and left legacy (no provenance): nothing is
// inferred to be the listener's edit.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/lyrics_provenance_schema.dart';
import 'package:sonus_next/core/database/schema/lyrics_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

const _stamp = '2026-11-01T00:00:00.000Z';

/// track_lyrics as version 47 had it, with three rows.
Future<Database> _version47() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  await db.execute(
    'CREATE TABLE ${DatabaseTables.songs} (id TEXT PRIMARY KEY NOT NULL)',
  );
  await LyricsSchema.create(db);
  for (final (id, plain, synced) in [
    ('song-1', 'Plain words', null),
    ('song-2', null, '[00:01.00]Timed'),
    ('song-3', 'Both plain', '[00:02.00]Both timed'),
  ]) {
    await db.insert(DatabaseTables.songs, {'id': id});
    await db.insert(DatabaseTables.trackLyrics, {
      'song_id': id,
      'plain_text': plain,
      'synced_text': synced,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
  }
  return db;
}

Future<List<Map<String, Object?>>> _columns(DatabaseExecutor db) =>
    db.rawQuery('PRAGMA table_info(${DatabaseTables.trackLyrics})');

Future<List<Map<String, Object?>>> _rows(DatabaseExecutor db) =>
    db.query(DatabaseTables.trackLyrics, orderBy: 'song_id');

void main() {
  sqfliteFfiInit();

  test('a fresh database is version 48 with every provenance column '
      'nullable', () async {
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      final db = await app.database;
      expect(AppDatabase.databaseVersion, 48);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        48,
      );
      final columns = {for (final c in await _columns(db)) c['name']: c};
      for (final name in LyricsProvenanceSchema.columnNames) {
        expect(columns[name]!['notnull'], 0, reason: name);
        expect(columns[name]!['dflt_value'], isNull, reason: name);
      }
    } finally {
      await app.close();
    }
  });

  test('47 to 48 keeps every row, text unchanged, provenance unset '
      '(legacy)', () async {
    final db = await _version47();
    try {
      final before = await _rows(db);
      await DatabaseMigrations.migrate(db, oldVersion: 47, newVersion: 48);
      final after = await _rows(db);

      expect(after, hasLength(3));
      for (final (index, row) in after.indexed) {
        for (final column in LyricsProvenanceSchema.columnNames) {
          expect(row[column], isNull, reason: column);
        }
        expect(
          {...row}..removeWhere(
            (k, _) => LyricsProvenanceSchema.columnNames.contains(k),
          ),
          before[index],
        );
      }

      // Running it again changes nothing.
      await DatabaseMigrations.migrate(db, oldVersion: 47, newVersion: 48);
      expect(await _rows(db), after);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
    } finally {
      await db.close();
    }
  });

  test('an upgraded lyrics table matches a fresh one', () async {
    final upgraded = await _version47();
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      await DatabaseMigrations.migrate(
        upgraded,
        oldVersion: 47,
        newVersion: 48,
      );
      expect(await _columns(upgraded), await _columns(await app.database));
    } finally {
      await upgraded.close();
      await app.close();
    }
  });

  group('checks', () {
    late Database db;

    setUp(() async {
      db = await _version47();
      await DatabaseMigrations.migrate(db, oldVersion: 47, newVersion: 48);
    });
    tearDown(() => db.close());

    Future<void> set(Map<String, Object?> values) => db.update(
      DatabaseTables.trackLyrics,
      values,
      where: 'song_id = ?',
      whereArgs: ['song-3'],
    );

    test('accept every valid shape', () async {
      for (final source in LyricsProvenanceSchema.sources) {
        await set({
          'plain_source': source,
          'plain_user_edited_at': source == 'user' ? _stamp : null,
          'synced_source': source,
          'synced_user_edited_at': source == 'user' ? _stamp : null,
        });
      }
      await set({
        'plain_source': 'generated',
        'plain_user_edited_at': null,
        'plain_confidence': 0.4,
        'offset_ms': -600000,
        'provider_licence': 'displayOnly',
      });
      await set({'offset_ms': 600000, 'provider_licence': 'cacheable'});
      await set({'offset_ms': null, 'provider_licence': null});
    });

    for (final (label, values) in <(String, Map<String, Object?>)>[
      ('an unknown source', {'plain_source': 'scraped'}),
      ('an unknown synced source', {'synced_source': 'lrclib'}),
      ('a user source without a stamp', {'plain_source': 'user'}),
      (
        'a stamp without the user source',
        {'synced_source': 'embedded', 'synced_user_edited_at': _stamp},
      ),
      (
        'a confidence on non-generated text',
        {'plain_source': 'embedded', 'plain_confidence': 0.9},
      ),
      (
        'a confidence above 1',
        {'synced_source': 'generated', 'synced_confidence': 1.5},
      ),
      ('an offset beyond 10 minutes', {'offset_ms': 600001}),
      ('an unknown licence', {'provider_licence': 'noStore'}),
    ]) {
      test('refuse $label', () async {
        await expectLater(set(values), throwsA(isA<DatabaseException>()));
      });
    }
  });

  test('backups carry provenance; older backups restore without it', () {
    final lyrics = BackupCoverageContract.tables.singleWhere(
      (c) => c.table == DatabaseTables.trackLyrics,
    );
    expect(lyrics.isPortable, isTrue);
    expect(lyrics.requiredInEveryBackup, isTrue);
    expect(
      lyrics.columnsAddedLater,
      LyricsProvenanceSchema.columnNames.toSet(),
    );
    expect(BackupCompatibility.restorableDatabaseVersions, contains(47));
    expect(BackupCompatibility.restorableDatabaseVersions, contains(48));
  });
}
