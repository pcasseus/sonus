// App Update 1.3 (database version 48): backups carry lyrics provenance,
// never display-only provider text; older (v47) backups restore as legacy;
// and a restore never replaces the listener's lyrics edit made here with
// the backup's automatic text. Disposable data only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/lyrics_provenance_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_json_codec.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';

import '../../support/recovery_fixtures.dart';

const _edited = '2026-11-10T00:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_lyrics_restore_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    await target.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> library(DatabaseExecutor db) async {
    await seedConnectedLibrary(db, key: 'a');
    await seedConnectedLibrary(db, key: 'b', week: 1);
  }

  Future<void> restore(DecodedBackup backup) async {
    final preflight = await RestorePreflightService(appDatabase: target).assess(
      VerifiedBackupContents(
        backup: backup,
        artwork: const [],
        directory: root,
      ),
    );
    expect(preflight.blockers, isEmpty);
    final db = await target.database;
    await db.transaction(
      (transaction) => const SqliteRestoreExecutor().apply(
        transaction: transaction,
        backup: backup,
        artworkPaths: const {},
      ),
    );
  }

  Future<Map<Object?, Map<String, Object?>>> lyrics() async => {
    for (final row in await (await target.database).query(
      DatabaseTables.trackLyrics,
    ))
      row['song_id']: row,
  };

  Future<void> setLyrics(
    DatabaseExecutor db,
    String song,
    Map<String, Object?> values,
  ) => db.update(
    DatabaseTables.trackLyrics,
    values,
    where: 'song_id = ?',
    whereArgs: [song],
  );

  test('a backup round trip keeps every provenance field', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await library(db);
        await setLyrics(db, 'song-a', {
          'plain_source': 'user',
          'plain_user_edited_at': _edited,
          'plain_updated_at': _edited,
          'synced_text': '[00:01.00]Guess',
          'synced_source': 'generated',
          'synced_confidence': 0.4,
          'offset_ms': -250,
          'offset_user_edited_at': _edited,
          'language': 'en',
        });
      },
    );
    expect(contents.backup.manifest.databaseVersion, 48);
    await restore(contents.backup);

    final a = (await lyrics())['song-a']!;
    expect(a['plain_text'], 'Lyrics a');
    expect(a['plain_source'], 'user');
    expect(a['plain_user_edited_at'], _edited);
    expect(a['synced_source'], 'generated');
    expect(a['synced_confidence'], 0.4);
    expect(a['offset_ms'], -250);
    expect(a['language'], 'en');
  });

  test('display-only provider text is never exported', () async {
    final source = fileAppDatabase(root, 'source.db');
    try {
      final db = await source.database;
      await library(db);
      await setLyrics(db, 'song-a', {
        'plain_text': 'Licensed a',
        'plain_source': 'provider',
        'synced_text': '[00:01.00]Own',
        'synced_source': 'sidecarLrc',
        'provider': 'p',
        'provider_licence': 'displayOnly',
      });
      await setLyrics(db, 'song-b', {
        'plain_text': 'Licensed b',
        'plain_source': 'provider',
        'provider': 'p',
        'provider_licence': 'displayOnly',
      });

      final exported = await SqliteBackupExporter(appDatabase: source).export();
      final rows = exported.payload.tables[DatabaseTables.trackLyrics]!;
      expect(rows, hasLength(1), reason: "song-b's row had nothing else");
      expect(rows.single['song_id'], 'song-a');
      expect(rows.single['plain_text'], isNull);
      expect(rows.single['provider_licence'], isNull);
      expect(rows.single['synced_text'], '[00:01.00]Own');
      expect(exported.manifest.rowCounts[DatabaseTables.trackLyrics], 1);
    } finally {
      await source.close();
    }
  });

  test('a version 47 backup restores its lyrics as legacy', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: library,
    );
    final current = contents.backup;
    final tables = {
      ...current.payload.tables,
      DatabaseTables.trackLyrics: [
        for (final row in current.payload.tables[DatabaseTables.trackLyrics]!)
          {...row}..removeWhere(
            (k, _) => LyricsProvenanceSchema.columnNames.contains(k),
          ),
      ],
    };
    final v47 = DecodedBackup(
      manifest: BackupManifest(
        backupId: 'v47',
        createdAtUtc: DateTime.utc(2026, 11, 14),
        databaseVersion: 47,
        rowCounts: current.manifest.rowCounts,
      ),
      payload: BackupDataPayload(tables: tables),
    );
    expect(
      v47.payload.tables[DatabaseTables.trackLyrics]!.first.containsKey(
        'plain_source',
      ),
      isFalse,
    );

    await restore(v47);

    final rows = await lyrics();
    expect(rows.keys, {'song-a', 'song-b'});
    expect(rows['song-a']!['plain_text'], 'Lyrics a');
    for (final row in rows.values) {
      for (final column in LyricsProvenanceSchema.columnNames) {
        expect(row[column], isNull, reason: column);
      }
    }
  });

  group('a restore keeps the listener edits made here', () {
    late DecodedBackup backup;

    setUp(() async {
      backup = (await verifiedFixtureContents(
        directory: root,
        seed: (db) async {
          await library(db);
          await setLyrics(db, 'song-a', {
            'plain_text': 'Backup embedded',
            'plain_source': 'embedded',
            'synced_text': '[00:01.00]Backup timed',
            'synced_source': 'sidecarLrc',
          });
          // song-b has no lyrics in the backup.
          await db.delete(
            DatabaseTables.trackLyrics,
            where: 'song_id = ?',
            whereArgs: ['song-b'],
          );
        },
      )).backup;
      await library(await target.database);
    });

    test('over the backup automatic text, text by text', () async {
      final db = await target.database;
      await setLyrics(db, 'song-a', {
        'plain_text': 'My words',
        'plain_source': 'user',
        'plain_user_edited_at': _edited,
        'offset_ms': 120,
        'offset_user_edited_at': _edited,
      });
      await setLyrics(db, 'song-b', {
        'synced_text': '[00:02.00]My timing',
        'synced_source': 'user',
        'synced_user_edited_at': _edited,
      });

      await restore(backup);

      final rows = await lyrics();
      expect(rows['song-a']!['plain_text'], 'My words');
      expect(rows['song-a']!['plain_source'], 'user');
      expect(rows['song-a']!['offset_ms'], 120);
      expect(rows['song-a']!['synced_text'], '[00:01.00]Backup timed');
      // The backup had none for song-b: only the edit is kept.
      expect(rows['song-b']!['synced_text'], '[00:02.00]My timing');
      expect(rows['song-b']!['plain_text'], isNull);
    });

    test('unless the backup holds a more recent edit of that text', () async {
      final newer = (await verifiedFixtureContents(
        directory: root,
        backupId: 'newer',
        seed: (db) async {
          await library(db);
          await setLyrics(db, 'song-a', {
            'plain_text': 'Later edit',
            'plain_source': 'user',
            'plain_user_edited_at': '2026-11-12T00:00:00.000Z',
          });
        },
      )).backup;
      await setLyrics(await target.database, 'song-a', {
        'plain_text': 'Earlier edit',
        'plain_source': 'user',
        'plain_user_edited_at': _edited,
      });

      await restore(newer);

      expect((await lyrics())['song-a']!['plain_text'], 'Later edit');
    });
  });
}
