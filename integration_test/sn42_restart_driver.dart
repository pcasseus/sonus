// SN-42 restart driver: a standalone app (not a test) run on the disposable
// emulator by `sn42_restart_driver.ps1`. Each launch performs the next
// phase and writes its observations to result_<phase>.json, so a REAL
// process kill and relaunch sit between phases.
//
//   kill      start a cloud-linked restore and block inside the SQLite
//             transaction; the host force-stops the app there.
//   recover   after relaunch: verify sync is blocked until the startup
//             check, run it, verify the interrupted restore was undone;
//             then complete a restore that must leave sync paused.
//   persist   after another relaunch: verify the pause survived.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';
import 'package:sonus_next/features/recovery/application/services/restored_artwork_installer.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_restore_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';

import '../test/support/library_seed.dart';
import 'support/device_test_root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('SN-42 restart driver')),
  ));

  final root = await fixedDeviceTestRoot('restart');
  await root.create(recursive: true);
  final driver = _Driver(root);

  try {
    if (!await driver.marker('kill_started').exists()) {
      await driver.phaseKill();
    } else if (!await driver.marker('recover_done').exists()) {
      await driver.phaseRecover();
    } else {
      await driver.phasePersist();
    }
  } catch (error, stack) {
    await driver.write('error', {'error': '$error', 'stack': '$stack'});
  }
}

class _Driver {
  _Driver(this.root);

  final Directory root;

  Directory get support => Directory(path.join(root.path, 'support'));
  Directory get recovery => Directory(path.join(support.path, 'sonus', 'recovery'));
  Directory get artwork => Directory(path.join(support.path, 'sonus', 'artwork'));

  File marker(String name) => File(path.join(root.path, '$name.marker'));

  Future<void> write(String phase, Map<String, Object?> result) =>
      File(path.join(root.path, 'result_$phase.json'))
          .writeAsString(jsonEncode(result), flush: true);

  AppDatabase target() =>
      AppDatabase(databasePath: path.join(root.path, 'target.db'));

  RecoverySyncGate gate({bool startupCheck = true}) => RecoverySyncGate(
    holdStore: RecoverySyncHoldStore(directory: () async => recovery),
    requiresStartupCheck: startupCheck,
  );

  SonusRestoreOrchestrator restorer(
    AppDatabase database,
    RecoverySyncGate gate, {
    SqliteRestoreExecutor executor = const SqliteRestoreExecutor(),
  }) => SonusRestoreOrchestrator(
    appDatabase: database,
    gate: gate,
    recoveryDirectory: () async => recovery,
    artworkDirectory: () async => artwork,
    executor: executor,
    installer: RestoredArtworkInstaller(
      storageFactory: (fileId) => FileSystemArtworkManagedStorage(
        applicationSupportDirectoryProvider: () async => support,
        fileIdGenerator: fileId,
      ),
    ),
    safetyBackupWriter: (destination) => SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(appDatabase: database),
    ).createBackup(destination: destination),
  );

  Future<File> backup(String id, {String songTitle = 'Song'}) async {
    final source = AppDatabase(databasePath: path.join(root.path, '$id-src.db'));
    final cover = File(path.join(root.path, 'old-device', '$id.jpg'));
    await cover.create(recursive: true);
    await cover.writeAsBytes([7, 7, 7, 7]);

    try {
      final db = await source.database;
      await seedConnectedLibrary(
        db,
        key: 'a',
        userId: 'user-1',
        artworkPath: cover.path,
        songTitle: songTitle,
      );
      await seedConnectedLibrary(db, key: 'b', week: 1, userId: 'user-1');

      return await SonusBackupOrchestrator(
        exporter: SqliteBackupExporter(appDatabase: source, generateId: () => id),
      ).createBackup(destination: File(path.join(root.path, '$id.sonusbackup')));
    } finally {
      await source.close();
    }
  }

  Future<String> syncState(RecoverySyncGate gate) async {
    try {
      await gate.guard(() async {});
      return 'allowed';
    } on SyncHeldForRecovery catch (held) {
      return 'held:${held.reason.name}';
    }
  }

  Future<void> phaseKill() async {
    await recovery.create(recursive: true);
    await artwork.create(recursive: true);

    final database = target();
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a', userId: 'user-1', songTitle: 'Before');
    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': 'user-1',
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'entity_id': 'artist-a',
      'server_revision': 1,
    });

    await File(path.join(root.path, 'before.json')).writeAsString(
      _digest(await snapshotDatabase(db)),
      flush: true,
    );

    final file = await backup('interrupted');
    final checkedGate = gate(startupCheck: false);

    await marker('kill_started').create();

    // Blocks forever inside the transaction, after artwork was installed
    // and rows were changed; the host kills the process here.
    await restorer(
      database,
      checkedGate,
      executor: SqliteRestoreExecutor(
        afterPhase: (phase) async {
          if (phase == RestorePhase.insertDependentTables) {
            await marker('inside_transaction').create();
            await Completer<void>().future;
          }
        },
      ),
    ).restore(file);
  }

  Future<void> phaseRecover() async {
    final result = <String, Object?>{};
    final journal = await RestoreJournalStore(directory: () async => recovery).read();
    final holdBefore = await RecoverySyncHoldStore(directory: () async => recovery).read();

    result['hold_after_kill'] = switch (holdBefore) {
      ActiveRecoverySyncHold(:final hold) => hold.phase.name,
      UnreadableRecoverySyncHold() => 'unreadable',
      NoRecoverySyncHold() => 'none',
    };
    result['journal_files_after_kill'] = journal?.createdFiles.length ?? 0;

    final database = target();
    final db = await database.database;
    final checkedGate = gate();

    result['sync_before_startup_check'] = await syncState(checkedGate);

    await checkedGate.runStartupCheck(
      () => restorer(database, checkedGate).reassessSyncHold(),
    );

    result['sync_after_startup_check'] = await syncState(checkedGate);
    result['db_matches_pre_restore'] =
        _digest(await snapshotDatabase(db)) ==
        await File(path.join(root.path, 'before.json')).readAsString();
    result['journal_files_remaining'] = [
      for (final file in journal?.createdFiles ?? const <String>[])
        if (await File(file).exists()) file,
    ].length;
    result['song_title'] =
        (await db.query(DatabaseTables.songs, where: 'id = ?', whereArgs: ['song-a']))
            .single['title'];

    // Now a completed cloud-linked restore that must leave sync paused.
    final file = await backup('completed', songTitle: 'Restored');
    final restore = await restorer(database, checkedGate).restore(file);
    result['completed_restore_sync_held'] = restore.syncHeld;
    result['sync_after_completed_restore'] = await syncState(checkedGate);

    await write('recover', result);
    await marker('recover_done').create();
  }

  Future<void> phasePersist() async {
    final database = target();
    final checkedGate = gate();
    final result = <String, Object?>{
      'sync_before_startup_check': await syncState(checkedGate),
    };

    await checkedGate.runStartupCheck(
      () => restorer(database, checkedGate).reassessSyncHold(),
    );

    final hold = await RecoverySyncHoldStore(directory: () async => recovery).read();
    result['sync_after_startup_check'] = await syncState(checkedGate);
    result['hold_phase'] = switch (hold) {
      ActiveRecoverySyncHold(:final hold) => hold.phase.name,
      UnreadableRecoverySyncHold() => 'unreadable',
      NoRecoverySyncHold() => 'none',
    };
    result['song_title'] =
        (await (await database.database).query(
          DatabaseTables.songs,
          where: 'id = ?',
          whereArgs: ['song-a'],
        )).single['title'];

    await write('persist', result);
    await database.close();
    // The host uninstalls the disposable app, removing all test data.
  }
}

String _digest(Object snapshot) =>
    sha256.convert(utf8.encode(jsonEncode('$snapshot'))).toString();
