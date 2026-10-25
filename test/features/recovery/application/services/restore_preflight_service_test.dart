import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/models/backup_compatibility.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/models/restore_preflight.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';

import '../../../../support/recovery_fixtures.dart';
import '../../../../support/sync_ledger_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;
  late RestorePreflightService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_preflight_');
    target = fileAppDatabase(root, 'target.db');
    service = RestorePreflightService(appDatabase: target);
  });

  tearDown(() async {
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> bindAccount(String userId) async {
    final db = await target.database;
    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': userId,
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshotAll() async {
    final db = await target.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    return {
      for (final row in tables)
        row['name'] as String: await db.query(row['name'] as String),
    };
  }

  /// Packages a hand-built backup, bypassing exporter-side validation, to
  /// represent backups from other versions or damaged sources.
  Future<VerifiedBackupContents> handBuiltContents({
    required int databaseVersion,
    Map<String, List<Map<String, Object?>>> rows = const {},
  }) async {
    final staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    final payload = BackupDataPayload(
      tables: {
        for (final entry in BackupCoverageContract.portableTables)
          entry.table: rows[entry.table] ?? <Map<String, Object?>>[],
      },
    );

    final manifest = BackupManifest(
      backupId: 'hand-built',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: databaseVersion,
      rowCounts: {
        for (final entry in payload.tables.entries)
          entry.key: entry.value.length,
      },
    );

    await File(path.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode({'manifest': manifest.toJson(), 'artwork': <Object>[]}),
    );
    await File(path.join(staging.path, 'library.json')).writeAsString(
      const BackupIntegrityCodec().encode(manifest: manifest, payload: payload),
    );

    final backup = await const BackupArchiveWriter().write(
      stagingDirectory: staging,
      destination: File(path.join(root.path, 'hand-built.sonusbackup')),
    );

    return const BackupArchiveVerifier().verifyAndExtract(
      backupFile: backup,
      targetDirectory: Directory(path.join(root.path, 'extract')),
    );
  }

  test('allows a compatible backup on a clean device', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, isEmpty);
    expect(result.canRestore, isTrue);
    expect(result.backupId, 'fixture-backup');
    expect(result.backupDatabaseVersion, AppDatabase.databaseVersion);
    expect(result.backupAccountIds, isEmpty);
    expect(result.localAccountId, isNull);
    expect(result.requiresSyncAssessment, isFalse);
    expect(result.estimatedRequiredBytes, greaterThan(0));
  });

  test('supports exactly the reviewed backup database versions', () {
    expect(BackupCompatibility.restorableDatabaseVersions, {
      31,
      32,
      33,
      34,
      35,
    });
    expect(
      BackupCompatibility.restorableDatabaseVersions,
      contains(AppDatabase.databaseVersion),
    );
  });

  for (final version in [31, 32]) {
    test('accepts a backup from supported database version $version', () async {
      final contents = await handBuiltContents(databaseVersion: version);

      final result = await service.assess(contents);

      expect(result.blockers, isEmpty);
      expect(result.backupDatabaseVersion, version);
    });
  }

  test('rejects backups older than the oldest supported version', () async {
    final contents = await handBuiltContents(databaseVersion: 30);

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.incompatibleBackupVersion]);
    expect(result.canRestore, isFalse);
  });

  test('rejects backups newer than this build', () async {
    await expectLater(
      handBuiltContents(databaseVersion: AppDatabase.databaseVersion + 1),
      throwsFormatException,
    );
  });

  test('validates older supported backups against the local schema', () async {
    final contents = await handBuiltContents(
      databaseVersion: 31,
      rows: {
        DatabaseTables.playlists: [
          {
            'id': 'playlist-1',
            'name': 'Mix',
            'created_at': fixtureTimestamp,
            'updated_at': fixtureTimestamp,
            'unexpected_column': 'x',
          },
        ],
      },
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.schemaMismatch]);
  });

  test('rejects restoring into a local database at another version', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );
    final db = await target.database;
    await db.execute(
      'PRAGMA user_version = ${AppDatabase.databaseVersion - 1}',
    );

    try {
      final result = await service.assess(contents);
      expect(result.blockers, [RestoreBlocker.incompatibleLocalDatabase]);
    } finally {
      await db.execute('PRAGMA user_version = ${AppDatabase.databaseVersion}');
    }
  });

  test('rejects rows that do not match the local schema', () async {
    final contents = await handBuiltContents(
      databaseVersion: AppDatabase.databaseVersion,
      rows: {
        DatabaseTables.playlists: [
          {
            'id': 'playlist-1',
            'name': 'Mix',
            'created_at': fixtureTimestamp,
            'updated_at': fixtureTimestamp,
            'unexpected_column': 'x',
          },
        ],
      },
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.schemaMismatch]);
  });

  test('blocks a backup owned by a different account', () async {
    await bindAccount('user-device');

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', userId: 'user-other'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.accountConflict]);
    expect(result.backupAccountIds, {'user-other'});
    expect(result.localAccountId, 'user-device');
  });

  test('accepts the same account and requires a sync assessment', () async {
    await bindAccount('user-1');

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', userId: 'user-1'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, isEmpty);
    expect(result.hasCloudSyncState, isTrue);
    expect(result.requiresSyncAssessment, isTrue);
  });

  test('an owned backup on an unbound device requires assessment', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', userId: 'user-1'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, isEmpty);
    expect(result.hasCloudSyncState, isFalse);
    expect(result.requiresSyncAssessment, isTrue);
  });

  test('blocks history spanning several accounts', () async {
    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a', userId: 'user-1');
        await seedConnectedLibrary(db, key: 'b', week: 1, userId: 'user-2');
      },
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.multipleBackupAccounts]);
  });

  test('blocks pending sync work without discarding it', () async {
    final db = await target.database;

    await db.insert(DatabaseTables.syncOutbox, {
      'id': 'outbox-1',
      'entity_type': 'artist',
      'entity_id': 'artist-local',
      'operation': 'upsert',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });

    await db.insert(SyncSchema.artistDependencyJournalTable, {
      'user_id': 'user-1',
      'artist_id': 'artist-local',
      'request_id': 'request-1',
      'request_json': '{}',
      'created_at': fixtureTimestamp,
    });

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.pendingSyncWork]);
    expect(result.pendingSyncItemCount, 2);
    expect(await db.query(DatabaseTables.syncOutbox), hasLength(1));
    expect(
      await db.query(SyncSchema.artistDependencyJournalTable),
      hasLength(1),
    );
  });

  test('cloud cursors alone mark the device as sync-associated', () async {
    final db = await target.database;

    await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'entity_id': 'artist-a',
      'server_revision': 3,
    });

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, isEmpty);
    expect(result.requiresSyncAssessment, isTrue);
  });

  test(
    'a deferred replay ledger marks the device as sync-associated',
    () async {
      await seedDeferredRecord(
        await target.database,
        userId: 'user-1',
        entityId: 'song-a',
      );

      final contents = await verifiedFixtureContents(
        directory: root,
        seed: (db) => seedConnectedLibrary(db, key: 'a'),
      );

      final result = await service.assess(contents);

      expect(result.blockers, isEmpty);
      expect(result.requiresSyncAssessment, isTrue);
    },
  );

  test('a conflict whose outbox entry is pending blocks the restore', () async {
    final db = await target.database;
    await db.insert(DatabaseTables.syncOutbox, {
      'id': 'outbox-conflict',
      'entity_type': 'song',
      'entity_id': 'song-a',
      'operation': 'upsert',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await seedOutboundConflict(db, userId: 'user-1', entityId: 'song-a');

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, [RestoreBlocker.pendingSyncWork]);
    expect(result.pendingSyncItemCount, 1);
    expect(result.requiresSyncAssessment, isTrue);
  });

  test('a conflict left without pending work needs assessment only', () async {
    await seedOutboundConflict(
      await target.database,
      userId: 'user-1',
      entityId: 'song-a',
    );

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a'),
    );

    final result = await service.assess(contents);

    expect(result.blockers, isEmpty);
    expect(result.requiresSyncAssessment, isTrue);
  });

  test('preflight never modifies the local database', () async {
    await bindAccount('user-device');
    await seedConnectedLibrary(await target.database, key: 'local');
    final before = await snapshotAll();

    final contents = await verifiedFixtureContents(
      directory: root,
      seed: (db) => seedConnectedLibrary(db, key: 'a', userId: 'user-other'),
    );

    await service.assess(contents);

    expect(await snapshotAll(), before);
  });
}
