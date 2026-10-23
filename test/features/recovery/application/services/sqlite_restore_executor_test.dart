import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';

import '../../../../support/recovery_fixtures.dart';

class _InjectedFailure implements Exception {}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_executor_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Map<String, String> devicePaths(VerifiedBackupContents contents) => {
    for (final row
        in contents.backup.payload.tables[DatabaseTables.artworkAssets]!)
      row['id'] as String: path.join(root.path, 'device', '${row['id']}.jpg'),
  };

  Future<void> apply(
    VerifiedBackupContents contents, {
    SqliteRestoreExecutor executor = const SqliteRestoreExecutor(),
  }) async {
    final db = await target.database;

    await db.transaction(
      (transaction) => executor.apply(
        transaction: transaction,
        backup: contents.backup,
        artworkPaths: devicePaths(contents),
      ),
    );
  }

  test('covers exactly the portable tables', () {
    expect(
      {
        ...SqliteRestoreExecutor.anchorTables,
        ...SqliteRestoreExecutor.dependentTables,
      },
      {for (final c in BackupCoverageContract.portableTables) c.table},
    );
  });

  test('restores every portable row verbatim onto an empty device', () async {
    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1, 2, 3]);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a', userId: 'user-1', artworkPath: cover.path);
        await seedConnectedLibrary(db, key: 'b', week: 1);
      },
    );

    await apply(contents);
    final db = await target.database;

    for (final coverage in BackupCoverageContract.portableTables) {
      final restored = await db.query(coverage.table);
      final expected = contents.backup.payload.tables[coverage.table]!;

      expect(restored, hasLength(expected.length), reason: coverage.table);

      if (coverage.table == DatabaseTables.artworkAssets) continue;

      expect(
        restored,
        unorderedEquals(expected),
        reason: '${coverage.table} must keep identities and values',
      );
    }

    final artwork = (await db.query(DatabaseTables.artworkAssets)).single;
    expect(artwork['id'], 'artwork-a');
    expect(artwork['file_path'], devicePaths(contents)['artwork-a']);
    expect(artwork['file_path'], isNot(cover.path));

    final play = (await db.query(DatabaseTables.qualifiedPlays))
        .firstWhere((row) => row['id'] == 'play-a');
    expect(play['user_id'], 'user-1');
    expect(play['playback_session_id'], 'session-a');
  });

  test('keeps device-local data of surviving songs only', () async {
    final db = await target.database;

    await seedConnectedLibrary(db, key: 'a', songTitle: 'Old Title');
    await seedConnectedLibrary(db, key: 'c', week: 2);
    await seedMediaBinding(db, key: 'a');
    await seedMediaBinding(db, key: 'c');
    await seedImportReview(db, key: 'a');
    await seedImportReview(db, key: 'c');

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a');
        await seedConnectedLibrary(db, key: 'b', week: 1);
      },
    );

    await apply(contents);

    final bindings = await db.query(DatabaseTables.mediaFileBindings);
    expect(bindings.map((row) => row['id']), ['binding-a']);
    expect(bindings.single['file_path'], '/device/music/a.mp3');

    final reviews = await db.query(DatabaseTables.songImportReviews);
    expect(reviews.map((row) => row['song_id']), ['song-a']);

    final songs = await db.query(DatabaseTables.songs, orderBy: 'id');
    expect(songs.map((row) => row['id']), ['song-a', 'song-b']);
    expect(songs.first['title'], 'Song');
  });

  test('never writes sync or account tables', () async {
    final db = await target.database;

    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': 'user-1',
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'entity_id': 'artist-gone',
      'server_revision': 4,
    });
    await db.insert(DatabaseTables.syncState, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'updated_at': fixtureTimestamp,
    });

    final syncTables = [
      DatabaseTables.localAccountBinding,
      DatabaseTables.syncState,
      DatabaseTables.syncOutbox,
      SyncSchema.cloudRevisionBaselinesTable,
      SyncSchema.artistWriteJournalTable,
      SyncSchema.artistDependencyJournalTable,
    ];

    final before = {for (final t in syncTables) t: await db.query(t)};

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', userId: 'user-1'),
    );

    await apply(contents);

    for (final table in syncTables) {
      expect(await db.query(table), before[table], reason: table);
    }
  });

  for (final phase in RestorePhase.values) {
    test('a failure after ${phase.name} rolls everything back', () async {
      final db = await target.database;
      final cover = File(path.join(root.path, 'local.jpg'));
      await cover.writeAsBytes([4, 4, 4]);

      await seedConnectedLibrary(db, key: 'a', songTitle: 'Local', artworkPath: cover.path);
      await seedConnectedLibrary(db, key: 'c', week: 2);
      await seedMediaBinding(db, key: 'c');
      await seedImportReview(db, key: 'c');

      final before = await snapshotDatabase(db);

      final contents = await verifiedFixtureContents(
        directory: root,
        seed: (db) async {
          await seedConnectedLibrary(db, key: 'a');
          await seedConnectedLibrary(db, key: 'b', week: 1);
        },
      );

      await expectLater(
        apply(
          contents,
          executor: SqliteRestoreExecutor(
            afterPhase: (current) async {
              if (current == phase) throw _InjectedFailure();
            },
          ),
        ),
        throwsA(isA<_InjectedFailure>()),
      );

      expect(await snapshotDatabase(db), before);
    });
  }

  test('a missing installed artwork path aborts before any change', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'c');
    final before = await snapshotDatabase(db);

    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1]);

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', artworkPath: cover.path),
    );

    await expectLater(
      db.transaction(
        (transaction) => const SqliteRestoreExecutor().apply(
          transaction: transaction,
          backup: contents.backup,
          artworkPaths: const {},
        ),
      ),
      throwsA(isA<RestoreIntegrityFailure>()),
    );

    expect(await snapshotDatabase(db), before);
  });
}
