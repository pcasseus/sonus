import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/restore_planner.dart';

import '../../../../support/recovery_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;
  late RestorePlanner planner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_planner_');
    target = fileAppDatabase(root, 'target.db');
    planner = RestorePlanner(appDatabase: target);
  });

  tearDown(() async {
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('derives primary keys from the live schema', () async {
    final db = await target.database;

    expect(
      await RestorePlanner.primaryKeyColumns(db, DatabaseTables.songs),
      ['id'],
    );
    expect(
      await RestorePlanner.primaryKeyColumns(
        db,
        DatabaseTables.albumEditionTracks,
      ),
      ['album_edition_id', 'song_id'],
    );
    expect(
      await RestorePlanner.primaryKeyColumns(
        db,
        DatabaseTables.metadataFieldStates,
      ),
      ['entity_type', 'entity_id', 'field_name'],
    );
    expect(
      await RestorePlanner.primaryKeyColumns(db, DatabaseTables.trackLyrics),
      ['song_id'],
    );

    for (final coverage in BackupCoverageContract.portableTables) {
      expect(
        await RestorePlanner.primaryKeyColumns(db, coverage.table),
        isNotEmpty,
        reason: coverage.table,
      );
    }
  });

  test('new device: everything is added and no safety backup needed', () async {
    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1, 2, 3]);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', artworkPath: cover.path),
    );

    final plan = await planner.plan(contents);

    expect(plan.tables, hasLength(20));
    expect(plan.totalRemoved, 0);
    expect(plan.totalUpdated, 0);
    expect(plan.totalAdded, contents.backup.payload.totalRows);
    expect(plan.requiresSafetyBackup, isFalse);
    expect(plan.deviceImpact.songsWithoutAudio, 1);
    expect(plan.deviceImpact.artworkInstalled, 1);
    expect(plan.deviceImpact.artworkReused, 0);
    expect(plan.deviceImpact.mediaBindingsKept, 0);
  });

  test('identical library: unchanged rows and reusable artwork', () async {
    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1, 2, 3]);

    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      artworkPath: cover.path,
    );
    await seedMediaBinding(await target.database, key: 'a');

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', artworkPath: cover.path),
    );

    final plan = await planner.plan(contents);

    expect(plan.totalAdded, 0);
    expect(plan.totalUpdated, 0);
    expect(plan.totalRemoved, 0);
    expect(plan.requiresSafetyBackup, isTrue);
    expect(plan.deviceImpact.artworkReused, 1);
    expect(plan.deviceImpact.artworkInstalled, 0);
    expect(plan.deviceImpact.mediaBindingsKept, 1);
    expect(plan.deviceImpact.songsWithoutAudio, 0);
  });

  test('overlapping library: added, updated, removed, and device impact', () async {
    final db = await target.database;

    // Local: song "a" with a different title, plus local-only "c".
    await seedConnectedLibrary(db, key: 'a', songTitle: 'Local Title');
    await seedConnectedLibrary(db, key: 'c', week: 2);
    await seedMediaBinding(db, key: 'a');
    await seedMediaBinding(db, key: 'c');
    await seedImportReview(db, key: 'a');
    await seedImportReview(db, key: 'c');

    // Backup: song "a" with the original title, plus backup-only "b".
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a');
        await seedConnectedLibrary(db, key: 'b', week: 1);
      },
    );

    final plan = await planner.plan(contents);
    final songs = plan.table(DatabaseTables.songs);

    expect(songs.added, 1);
    expect(songs.updated, 1);
    expect(songs.unchanged, 0);
    expect(songs.removed, 1);

    final artists = plan.table(DatabaseTables.artists);
    expect(artists.added, 1);
    expect(artists.unchanged, 1);
    expect(artists.removed, 1);

    expect(plan.deviceImpact.mediaBindingsKept, 1);
    expect(plan.deviceImpact.mediaBindingsRemoved, 1);
    expect(plan.deviceImpact.importReviewsKept, 1);
    expect(plan.deviceImpact.importReviewsRemoved, 1);
    expect(plan.deviceImpact.songsWithoutAudio, 1);
    expect(plan.requiresSafetyBackup, isTrue);
  });

  test('unavailable audio still counts as missing after restore', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a');
    await seedMediaBinding(db, key: 'a', available: false);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final plan = await planner.plan(contents);

    expect(plan.deviceImpact.mediaBindingsKept, 1);
    expect(plan.deviceImpact.songsWithoutAudio, 1);
  });

  test('artwork paths are device-local and do not count as changes', () async {
    final backupCover = File(path.join(root.path, 'old-device.jpg'));
    final localCover = File(path.join(root.path, 'this-device.jpg'));
    await backupCover.writeAsBytes([5, 6, 7]);
    await localCover.writeAsBytes([5, 6, 7]);

    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      artworkPath: localCover.path,
    );

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) =>
          seedConnectedLibrary(db, key: 'a', artworkPath: backupCover.path),
    );

    final plan = await planner.plan(contents);

    expect(plan.table(DatabaseTables.artworkAssets).unchanged, 1);
    expect(plan.deviceImpact.artworkReused, 1);
  });

  test('changed local artwork bytes are reinstalled, not reused', () async {
    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1, 2, 3]);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', artworkPath: cover.path),
    );

    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      artworkPath: cover.path,
    );
    await cover.writeAsBytes([3, 2, 1]);

    final plan = await planner.plan(contents);

    expect(plan.deviceImpact.artworkReused, 0);
    expect(plan.deviceImpact.artworkInstalled, 1);
  });

  test('planning never modifies the local database', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'c');
    await seedMediaBinding(db, key: 'c');

    final before = {
      for (final table in [
        ...BackupCoverageContract.portableTables.map((c) => c.table),
        DatabaseTables.mediaFileBindings,
      ])
        table: await db.query(table),
    };

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    await planner.plan(contents);

    for (final entry in before.entries) {
      expect(await db.query(entry.key), entry.value, reason: entry.key);
    }
  });
}
