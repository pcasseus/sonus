import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/models/restore_preflight.dart';
import 'package:sonus_next/features/recovery/application/models/restore_result.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_fingerprint_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';
import 'package:sonus_next/features/recovery/application/services/restored_artwork_installer.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_restore_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';

import '../../../../support/recovery_fixtures.dart';
import '../../../../support/test_only_backup_publication.dart';

class _InjectedFailure implements Exception {
  const _InjectedFailure(this.stage);

  final String stage;

  @override
  String toString() => '_InjectedFailure($stage)';
}

/// Simulates a device where cleaning up after a failure itself fails.
class _BrokenJournalRecovery extends RestoreJournalRecovery {
  const _BrokenJournalRecovery({
    required super.journalStore,
    required super.artworkDirectory,
  });

  @override
  Future<RestoreJournalCleanup> discard(
    RestoreJournal journal,
    DatabaseExecutor executor,
  ) async {
    throw const FileSystemException('Storage became unavailable.');
  }
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late Directory support;
  late Directory artworkDir;
  late Directory recoveryDir;
  late Directory sourceDir;
  late AppDatabase target;
  late RecoverySyncGate gate;
  late int sessionCounter;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_restore_');
    support = Directory(path.join(root.path, 'support'));
    artworkDir = Directory(path.join(support.path, 'sonus', 'artwork'));
    recoveryDir = Directory(path.join(support.path, 'sonus', 'recovery'));
    sourceDir = Directory(path.join(root.path, 'old-device'));
    await artworkDir.create(recursive: true);
    await sourceDir.create(recursive: true);

    target = fileAppDatabase(root, 'target.db');
    gate = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => recoveryDir),
    );
    sessionCounter = 0;
  });

  tearDown(() async {
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<File> sourceArtwork(String name, List<int> bytes) async {
    final file = File(path.join(sourceDir.path, 'art', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<File> localArtwork(String name, List<int> bytes) async {
    final file = File(path.join(artworkDir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<File> backupOf(
    String id,
    Future<void> Function(DatabaseExecutor db) seed,
  ) async {
    final source = fileAppDatabase(sourceDir, '$id.db');

    try {
      await seed(await source.database);
      return await createFixtureBackup(
        source: source,
        directory: sourceDir,
        backupId: id,
        fileName: '$id.sonusbackup',
      );
    } finally {
      await source.close();
    }
  }

  SonusRestoreOrchestrator orchestrator({
    Future<void> Function(ExtractedBackupArtwork artwork)? beforeInstall,
    SqliteRestoreExecutor executor = const SqliteRestoreExecutor(),
    SafetyBackupWriter? safetyBackupWriter,
    RestoreJournalRecovery? journalRecovery,
    RecoverySyncGate? withGate,
  }) {
    return SonusRestoreOrchestrator(
      appDatabase: target,
      gate: withGate ?? gate,
      recoveryDirectory: () async => recoveryDir,
      artworkDirectory: () async => artworkDir,
      storageProbe: null,
      installer: RestoredArtworkInstaller(
        storageFactory: (fileId) => FileSystemArtworkManagedStorage(
          applicationSupportDirectoryProvider: () async => support,
          fileIdGenerator: fileId,
        ),
        beforeInstall: beforeInstall,
      ),
      executor: executor,
      journalRecovery: journalRecovery,
      safetyBackupWriter:
          safetyBackupWriter ??
          (destination) => SonusBackupOrchestrator(
            exporter: SqliteBackupExporter(appDatabase: target),
            publisher: const VerifiedBackupPublisher(
              publication: TestOnlyBackupPublication(),
            ),
          ).createBackup(destination: destination),
      now: () => DateTime.utc(2026, 10, 21, 12),
      generateSessionId: () => 'session${sessionCounter++}',
    );
  }

  Future<void> bindAccount(String userId, {bool withBaseline = true}) async {
    final db = await target.database;

    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': userId,
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });

    if (withBaseline) {
      await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
        'user_id': userId,
        'entity_type': 'artist',
        'entity_id': 'artist-a',
        'server_revision': 2,
      });
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> syncTables() async {
    final db = await target.database;
    return {
      for (final table in RecoveryFingerprintService.syncStateTables)
        table: await db.query(table),
    };
  }

  Future<bool> syncAllowed([RecoverySyncGate? withGate]) async {
    try {
      await (withGate ?? gate).guard(() async {});
      return true;
    } on SyncHeldForRecovery {
      return false;
    }
  }

  Future<RecoverySyncHoldState> holdState() =>
      RecoverySyncHoldStore(directory: () async => recoveryDir).read();

  Future<void> expectNoSessionLeftovers() async {
    expect(
      await File(
        path.join(recoveryDir.path, RestoreJournalStore.fileName),
      ).exists(),
      isFalse,
      reason: 'restore journal remained',
    );

    if (await recoveryDir.exists()) {
      final names = await recoveryDir
          .list()
          .map((entity) => path.basename(entity.path))
          .toList();

      expect(
        names.where((name) => name.startsWith('.sonus_')),
        isEmpty,
        reason: 'temporary restore data remained',
      );
      expect(
        names.where((name) => name.endsWith('.tmp')),
        isEmpty,
        reason: 'a state-file temporary remained',
      );
    }
  }

  test('new device: restores identities and installs device-local artwork', () async {
    final cover = await sourceArtwork('cover.jpg', [1, 2, 3, 4]);
    final backup = await backupOf('new-device', (db) async {
      await seedConnectedLibrary(db, key: 'a', artworkPath: cover.path);
      await seedConnectedLibrary(db, key: 'b', week: 1);
    });

    final stages = <RestoreStage>[];
    final result = await orchestrator().restore(backup, onProgress: stages.add);
    final db = await target.database;

    expect(result.backupId, 'new-device');
    expect(result.safetyBackup, isNull);
    expect(result.artworkInstalled, 1);
    expect(result.syncHeld, isFalse);
    expect(stages.last, RestoreStage.completed);
    expect(stages, isNot(contains(RestoreStage.creatingSafetyBackup)));

    final songs = await db.query(DatabaseTables.songs, orderBy: 'id');
    expect(songs.map((row) => row['id']), ['song-a', 'song-b']);

    final artwork = (await db.query(DatabaseTables.artworkAssets)).single;
    final installedPath = artwork['file_path'] as String;
    expect(path.isWithin(artworkDir.path, installedPath), isTrue);
    expect(await File(installedPath).readAsBytes(), [1, 2, 3, 4]);

    // Old-device paths never reach the database.
    final everything = await snapshotDatabase(db);
    expect(everything.toString(), isNot(contains(sourceDir.path)));

    expect(await holdState(), isA<NoRecoverySyncHold>());
    expect(await syncAllowed(), isTrue);
    expect(gate.isRestoreActive, isFalse);
    await expectNoSessionLeftovers();
  });

  test('existing data: a verified safety backup preserves it first', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'a', songTitle: 'Local Title');

    final backup = await backupOf('replacement', (db) async {
      await seedConnectedLibrary(db, key: 'b');
    });

    final result = await orchestrator().restore(backup);

    final safety = result.safetyBackup!;
    expect(path.isWithin(recoveryDir.path, safety.path), isTrue);

    final preserved = await const BackupArchiveVerifier().verify(safety);
    expect(
      preserved.payload.tables[DatabaseTables.songs]!.single['title'],
      'Local Title',
    );

    final songs = await db.query(DatabaseTables.songs);
    expect(songs.map((row) => row['id']), ['song-b']);
  });

  test('a blocked restore changes nothing', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'local');
    await db.insert(DatabaseTables.syncOutbox, {
      'id': 'pending-1',
      'entity_type': 'artist',
      'entity_id': 'artist-local',
      'operation': 'upsert',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    final before = await snapshotDatabase(db);

    final backup = await backupOf('blocked', (db) async {
      await seedConnectedLibrary(db, key: 'a');
    });

    await expectLater(
      orchestrator().restore(backup),
      throwsA(
        isA<RestoreBlockedException>().having(
          (e) => e.preflight.blockers,
          'blockers',
          [RestoreBlocker.pendingSyncWork],
        ),
      ),
    );

    expect(await snapshotDatabase(db), before);
    expect(await holdState(), isA<NoRecoverySyncHold>());
    await expectNoSessionLeftovers();
  });

  group('failure at every stage restores the previous state exactly', () {
    late Map<String, List<Map<String, Object?>>> before;
    late Map<String, List<int>> artworkBefore;
    late File backup;

    setUp(() async {
      final db = await target.database;
      final local = await localArtwork('artwork_local.jpg', [7, 7, 7]);
      await seedConnectedLibrary(db, key: 'a', songTitle: 'Local', artworkPath: local.path);
      await seedConnectedLibrary(db, key: 'c', week: 3);
      await seedMediaBinding(db, key: 'a');
      await seedMediaBinding(db, key: 'c');
      await seedImportReview(db, key: 'c');

      final coverA = await sourceArtwork('a.jpg', [1, 1, 1]);
      final coverB = await sourceArtwork('b.png', [2, 2]);
      backup = await backupOf('failing', (db) async {
        await seedConnectedLibrary(db, key: 'a', artworkPath: coverA.path);
        await seedConnectedLibrary(db, key: 'b', week: 1, artworkPath: coverB.path);
      });

      before = await snapshotDatabase(db);
      artworkBefore = await snapshotFiles(artworkDir);
    });

    Future<void> expectCleanFailure(
      SonusRestoreOrchestrator subject,
      RestoreStage stage,
    ) async {
      await expectLater(
        subject.restore(backup),
        throwsA(
          isA<RestoreFailedException>()
              .having((e) => e.stage, 'stage', stage)
              .having((e) => e.rollbackVerified, 'rollbackVerified', isTrue)
              .having((e) => e.syncHoldPreserved, 'holdPreserved', isFalse),
        ),
      );

      expect(await snapshotDatabase(await target.database), before);
      expect(await snapshotFiles(artworkDir), artworkBefore);
      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(await syncAllowed(), isTrue);
      expect(gate.isRestoreActive, isFalse);
      await expectNoSessionLeftovers();
    }

    test('safety backup creation', () async {
      await expectCleanFailure(
        orchestrator(
          safetyBackupWriter: (_) async =>
              throw const _InjectedFailure('safety'),
        ),
        RestoreStage.creatingSafetyBackup,
      );
    });

    test('safety backup verification', () async {
      await expectCleanFailure(
        orchestrator(
          safetyBackupWriter: (destination) async {
            await destination.writeAsBytes([0, 1, 2, 3]);
            return destination;
          },
        ),
        RestoreStage.creatingSafetyBackup,
      );
    });

    for (final failingInstall in [1, 2]) {
      test('artwork install #$failingInstall', () async {
        var installs = 0;

        await expectCleanFailure(
          orchestrator(
            beforeInstall: (_) async {
              if (++installs == failingInstall) {
                throw const _InjectedFailure('artwork');
              }
            },
          ),
          RestoreStage.installingArtwork,
        );
      });
    }

    for (final phase in RestorePhase.values) {
      test('database phase ${phase.name}', () async {
        await expectCleanFailure(
          orchestrator(
            executor: SqliteRestoreExecutor(
              afterPhase: (current) async {
                if (current == phase) throw _InjectedFailure(phase.name);
              },
            ),
          ),
          RestoreStage.restoringDatabase,
        );
      });
    }

    test('an unverifiable rollback keeps sync paused', () async {
      final journalStore = RestoreJournalStore(
        directory: () async => recoveryDir,
      );

      await expectLater(
        orchestrator(
          journalRecovery: _BrokenJournalRecovery(
            journalStore: journalStore,
            artworkDirectory: () async => artworkDir,
          ),
          executor: SqliteRestoreExecutor(
            afterPhase: (current) async {
              if (current == RestorePhase.insertDependentTables) {
                throw const _InjectedFailure('database');
              }
            },
          ),
        ).restore(backup),
        throwsA(
          isA<RestoreFailedException>()
              .having((e) => e.rollbackVerified, 'rollbackVerified', isFalse)
              .having((e) => e.syncHoldPreserved, 'holdPreserved', isTrue),
        ),
      );

      // The original database survives the rollback regardless.
      expect(await snapshotDatabase(await target.database), before);

      final state = await holdState();
      expect(state, isA<ActiveRecoverySyncHold>());
      expect(
        (state as ActiveRecoverySyncHold).hold.phase,
        RecoverySyncHoldPhase.restoreFailed,
      );
      expect(await syncAllowed(), isFalse);

      // Later recovery cleans up and proves nothing changed.
      final assessment = await orchestrator().reassessSyncHold();

      expect(assessment.isConclusivelyConsistent, isTrue);
      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(await snapshotFiles(artworkDir), artworkBefore);
      expect(await syncAllowed(), isTrue);
    });
  });

  test('an active sync finishes before restore changes begin', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'local');
    final before = await snapshotDatabase(db);

    final backup = await backupOf('during-sync', (db) async {
      await seedConnectedLibrary(db, key: 'a');
    });

    final started = Completer<void>();
    final release = Completer<void>();
    final activeSync = gate.guard(() {
      started.complete();
      return release.future;
    });
    await started.future;

    // The gate is claimed synchronously right after this stage is reported,
    // so waiting on it is deterministic regardless of machine load.
    final pausing = Completer<void>();
    final restore = orchestrator().restore(
      backup,
      onProgress: (stage) {
        if (stage == RestoreStage.pausingSync && !pausing.isCompleted) {
          pausing.complete();
        }
      },
    );

    await pausing.future;
    await Future<void>.delayed(Duration.zero);
    expect(gate.isRestoreActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await snapshotDatabase(db), before);
    expect(await syncAllowed(), isFalse);

    release.complete();
    await activeSync;
    final result = await restore;

    expect(result.backupId, 'during-sync');
    expect(
      (await db.query(DatabaseTables.songs)).map((row) => row['id']),
      ['song-a'],
    );
  });

  test('a cloud-linked restore with library changes stays paused', () async {
    await bindAccount('user-1');
    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      userId: 'user-1',
      songTitle: 'Before',
    );
    final syncBefore = await syncTables();

    final backup = await backupOf('cloud', (db) async {
      await seedConnectedLibrary(db, key: 'a', userId: 'user-1');
      await seedConnectedLibrary(db, key: 'b', week: 1, userId: 'user-1');
    });

    final result = await orchestrator().restore(backup);

    expect(result.syncHeld, isTrue);
    expect(
      result.syncAssessment.findings,
      contains(RecoverySyncFinding.cloudLibraryDiverged),
    );
    expect(result.syncAssessment.divergedTables, contains(DatabaseTables.songs));

    final state = await holdState() as ActiveRecoverySyncHold;
    expect(state.hold.phase, RecoverySyncHoldPhase.assessmentRequired);
    expect(await syncTables(), syncBefore);

    // Automatic and manual sync both go through the guard.
    await expectLater(
      gate.guard(() async {}),
      throwsA(
        isA<SyncHeldForRecovery>().having(
          (e) => e.reason,
          'reason',
          SyncHoldReason.assessmentRequired,
        ),
      ),
    );

    // After an app restart the hold still applies.
    final restarted = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => recoveryDir),
    );
    expect(await syncAllowed(restarted), isFalse);

    // Re-checking never releases an inconclusive hold.
    final again = await orchestrator(withGate: restarted).reassessSyncHold();
    expect(again.isConclusivelyConsistent, isFalse);
    expect(await syncAllowed(restarted), isFalse);
  });

  test('sync resumes only when cloud content is provably unchanged', () async {
    await bindAccount('user-1');
    final cover = await localArtwork('artwork_shared.jpg', [5, 5, 5]);
    await seedConnectedLibrary(
      await target.database,
      key: 'a',
      userId: 'user-1',
      artworkPath: cover.path,
    );

    // Same library; only non-cloud data (a playlist) differs.
    final backup = await backupOf('same-library', (db) async {
      await seedConnectedLibrary(
        db,
        key: 'a',
        userId: 'user-1',
        artworkPath: cover.path,
      );
      await db.insert(DatabaseTables.playlists, {
        'id': 'playlist-extra',
        'name': 'Recovered Mix',
        'created_at': fixtureTimestamp,
        'updated_at': fixtureTimestamp,
      });
    });

    final result = await orchestrator().restore(backup);

    expect(result.artworkReused, 1);
    expect(result.syncAssessment.findings, isEmpty);
    expect(result.syncHeld, isFalse);
    expect(await holdState(), isA<NoRecoverySyncHold>());
    expect(await syncAllowed(), isTrue);
  });

  test('history owned by an unconfirmed account stays paused', () async {
    final backup = await backupOf('unconfirmed', (db) async {
      await seedConnectedLibrary(db, key: 'a', userId: 'user-x');
    });

    final result = await orchestrator().restore(backup);

    expect(result.syncHeld, isTrue);
    expect(
      result.syncAssessment.findings,
      contains(RecoverySyncFinding.accountUnconfirmed),
    );
    expect(await syncAllowed(), isFalse);
  });

  test('an interrupted restore that never committed is recovered', () async {
    await bindAccount('user-1');
    final db = await target.database;
    final local = await localArtwork('artwork_local.jpg', [9, 9]);
    await seedConnectedLibrary(db, key: 'a', userId: 'user-1', artworkPath: local.path);
    final before = await snapshotDatabase(db);

    // State left behind by a process killed mid-restore.
    final store = RecoverySyncHoldStore(directory: () async => recoveryDir);
    await store.write(
      RecoverySyncHold(
        holdId: 'crashed',
        backupId: 'crashed-backup',
        createdAtUtc: DateTime.utc(2026, 10, 21),
        phase: RecoverySyncHoldPhase.restoring,
        backupAccountIds: const {'user-1'},
        preRestore: await const RecoveryFingerprintService().capture(db),
      ),
    );

    final orphan = await localArtwork('artwork_restorecrashedn0.jpg', [1]);
    final reservedOnly = await localArtwork('artwork_restorecrashedn1.png', [2]);
    final extraction = Directory(
      path.join(recoveryDir.path, '.sonus_restore_crashed'),
    );
    await extraction.create(recursive: true);

    await RestoreJournalStore(directory: () async => recoveryDir).write(
      RestoreJournal(
        sessionId: 'crashed',
        extractionDirectory: extraction.path,
        reservedTokens: const ['restorecrashedn0', 'restorecrashedn1'],
        createdFiles: [orphan.path],
      ),
    );

    // After restart, sync is still paused.
    expect(await syncAllowed(), isFalse);

    final assessment = await orchestrator().reassessSyncHold();

    expect(assessment.isConclusivelyConsistent, isTrue);
    expect(await orphan.exists(), isFalse);
    expect(await reservedOnly.exists(), isFalse);
    expect(await extraction.exists(), isFalse);
    expect(await local.readAsBytes(), [9, 9]);
    expect(await snapshotDatabase(db), before);
    expect(await holdState(), isA<NoRecoverySyncHold>());
    expect(await syncAllowed(), isTrue);
  });

  test('an interrupted restore after commit keeps its files and the hold', () async {
    await bindAccount('user-1');
    await seedConnectedLibrary(await target.database, key: 'old', userId: 'user-1');

    final cover = await sourceArtwork('cover.jpg', [3, 3, 3]);
    final backup = await backupOf('committed', (db) async {
      await seedConnectedLibrary(db, key: 'a', userId: 'user-1', artworkPath: cover.path);
    });

    await orchestrator().restore(backup);

    final db = await target.database;
    final installed =
        (await db.query(DatabaseTables.artworkAssets)).single['file_path']
            as String;

    // Simulate a crash after commit but before cleanup and assessment.
    final store = RecoverySyncHoldStore(directory: () async => recoveryDir);
    final held = await store.read() as ActiveRecoverySyncHold;
    await store.write(held.hold.copyWith(phase: RecoverySyncHoldPhase.restoring));
    await RestoreJournalStore(directory: () async => recoveryDir).write(
      RestoreJournal(
        sessionId: 'session0',
        extractionDirectory: path.join(recoveryDir.path, '.sonus_restore_x'),
        reservedTokens: const ['restoresession0n0'],
        createdFiles: [installed],
      ),
    );

    final assessment = await orchestrator().reassessSyncHold();

    expect(await File(installed).readAsBytes(), [3, 3, 3]);
    expect(assessment.isConclusivelyConsistent, isFalse);
    final state = await holdState() as ActiveRecoverySyncHold;
    expect(state.hold.phase, RecoverySyncHoldPhase.assessmentRequired);
    expect(await syncAllowed(), isFalse);
  });

  test('no restore before the startup recovery check has passed', () async {
    final checkedGate = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => recoveryDir),
      requiresStartupCheck: true,
    );
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'local');
    final before = await snapshotDatabase(db);

    final backup = await backupOf('too-early', (db) async {
      await seedConnectedLibrary(db, key: 'a');
    });

    await expectLater(
      orchestrator(withGate: checkedGate).restore(backup),
      throwsA(isA<RecoveryGateUnavailable>()),
    );
    expect(await snapshotDatabase(db), before);

    await checkedGate.runStartupCheck(
      () => orchestrator(withGate: checkedGate).reassessSyncHold(),
    );
    final result = await orchestrator(withGate: checkedGate).restore(backup);
    expect(result.backupId, 'too-early');
  });

  test('a second restore cannot start while one owns the gate', () async {
    final backup = await backupOf('second', (db) async {
      await seedConnectedLibrary(db, key: 'a');
    });

    await gate.beginRestore(
      (_) => RecoverySyncHold(
        holdId: 'first',
        backupId: 'first',
        createdAtUtc: DateTime.utc(2026, 10, 21),
        phase: RecoverySyncHoldPhase.restoring,
        backupAccountIds: const {},
        preRestore: null,
      ),
    );

    try {
      await expectLater(
        orchestrator().restore(backup),
        throwsA(isA<RecoveryGateUnavailable>()),
      );
    } finally {
      gate.endRestore();
    }
  });

  group('A04: conditions are decided again once sync has quiesced', () {
    Future<void> drainingSyncThen(
      Future<void> Function() duringDrain,
      Future<void> Function(Future<RestoreResult> restore) expectOutcome,
      File backup,
    ) async {
      final started = Completer<void>();
      final release = Completer<void>();
      final activeSync = gate.guard(() async {
        started.complete();
        await release.future;
        await duringDrain();
      });
      await started.future;

      // The first preflight has passed once sync pausing is reported.
      final pausing = Completer<void>();
      final restore = orchestrator().restore(
        backup,
        onProgress: (stage) {
          if (stage == RestoreStage.pausingSync && !pausing.isCompleted) {
            pausing.complete();
          }
        },
      );

      await pausing.future;
      release.complete();
      await activeSync;
      await expectOutcome(restore);
    }

    test('pending work left by a draining sync run blocks the restore', () async {
      final db = await target.database;
      await seedConnectedLibrary(db, key: 'local');
      final backup = await backupOf('stale-pending', (db) async {
        await seedConnectedLibrary(db, key: 'a');
      });

      await drainingSyncThen(
        () => db.insert(DatabaseTables.syncOutbox, {
          'id': 'requeued-1',
          'entity_type': 'artist',
          'entity_id': 'artist-local',
          'operation': 'upsert',
          'created_at': fixtureTimestamp,
          'updated_at': fixtureTimestamp,
        }),
        (restore) => expectLater(
          restore,
          throwsA(
            isA<RestoreBlockedException>().having(
              (e) => e.preflight.blockers,
              'blockers',
              [RestoreBlocker.pendingSyncWork],
            ),
          ),
        ),
        backup,
      );

      expect(
        (await db.query(DatabaseTables.songs)).map((row) => row['id']),
        ['song-local'],
      );
      expect(await db.query(DatabaseTables.syncOutbox), hasLength(1));
      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(await syncAllowed(), isTrue);
      expect(gate.isRestoreActive, isFalse);
      await expectNoSessionLeftovers();
    });

    test('a sign-in to another account during the drain blocks the restore', () async {
      final db = await target.database;
      await seedConnectedLibrary(db, key: 'local');
      final backup = await backupOf('stale-account', (db) async {
        await seedConnectedLibrary(db, key: 'a', userId: 'user-1');
      });

      await drainingSyncThen(
        () => bindAccount('user-2', withBaseline: false),
        (restore) => expectLater(
          restore,
          throwsA(
            isA<RestoreBlockedException>().having(
              (e) => e.preflight.blockers,
              'blockers',
              [RestoreBlocker.accountConflict],
            ),
          ),
        ),
        backup,
      );

      expect(
        (await db.query(DatabaseTables.songs)).map((row) => row['id']),
        ['song-local'],
      );
      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(gate.isRestoreActive, isFalse);
      await expectNoSessionLeftovers();
    });

    group('a local change after quiescence abandons the transaction', () {
      late File backup;
      late Map<String, List<int>> artworkBefore;

      setUp(() async {
        final db = await target.database;
        await seedConnectedLibrary(db, key: 'local', songTitle: 'Local');
        final cover = await sourceArtwork('cover.jpg', [4, 4, 4]);
        backup = await backupOf('changed', (db) async {
          await seedConnectedLibrary(db, key: 'a', artworkPath: cover.path);
        });
        artworkBefore = await snapshotFiles(artworkDir);
      });

      Future<RestoreConditionsChangedException> expectAbandoned(
        Future<void> Function(DatabaseExecutor db) change,
      ) async {
        final db = await target.database;
        Object? failure;

        try {
          await orchestrator(beforeInstall: (_) => change(db)).restore(backup);
        } catch (error) {
          failure = error;
        }

        expect(
          failure,
          isA<RestoreFailedException>()
              .having((e) => e.stage, 'stage', RestoreStage.restoringDatabase)
              .having((e) => e.rollbackVerified, 'rollbackVerified', isTrue)
              .having((e) => e.syncHoldPreserved, 'holdPreserved', isFalse)
              .having(
                (e) => e.cause,
                'cause',
                isA<RestoreConditionsChangedException>(),
              ),
        );

        // Nothing from the backup replaced the local library.
        expect(
          (await db.query(DatabaseTables.songs)).map((row) => row['id']),
          ['song-local'],
        );
        expect(await snapshotFiles(artworkDir), artworkBefore);
        expect(await holdState(), isA<NoRecoverySyncHold>());
        expect(await syncAllowed(), isTrue);
        expect(gate.isRestoreActive, isFalse);
        await expectNoSessionLeftovers();

        return (failure! as RestoreFailedException).cause
            as RestoreConditionsChangedException;
      }

      test('queued outbound work is kept and blocks the restore', () async {
        final change = await expectAbandoned(
          (db) => db.insert(DatabaseTables.syncOutbox, {
            'id': 'local-edit-1',
            'entity_type': 'song',
            'entity_id': 'song-local',
            'operation': 'upsert',
            'created_at': fixtureTimestamp,
            'updated_at': fixtureTimestamp,
          }),
        );

        expect(change.blockers, [RestoreBlocker.pendingSyncWork]);
        expect(change.changedTables, contains(DatabaseTables.syncOutbox));
        expect(
          await (await target.database).query(DatabaseTables.syncOutbox),
          hasLength(1),
        );
      });

      test('a library edit is kept rather than silently replaced', () async {
        final change = await expectAbandoned(
          (db) => db.update(
            DatabaseTables.songs,
            {'title': 'Edited during restore'},
            where: 'id = ?',
            whereArgs: ['song-local'],
          ),
        );

        expect(change.blockers, isEmpty);
        expect(change.changedTables, [DatabaseTables.songs]);
        final song = (await (await target.database).query(
          DatabaseTables.songs,
        )).single;
        expect(song['title'], 'Edited during restore');
      });

      test('an account sign-in is kept and blocks the restore', () async {
        final change = await expectAbandoned((db) async {
          await db.insert(DatabaseTables.localAccountBinding, {
            'id': 1,
            'user_id': 'user-9',
            'bound_at': fixtureTimestamp,
            'updated_at': fixtureTimestamp,
          });
        });

        expect(change.changedTables, contains(DatabaseTables.localAccountBinding));
      });
    });
  });

  test('local admission refusal restores the previous sync hold', () async {
    final db = await target.database;
    await seedConnectedLibrary(db, key: 'local');

    final backup = await backupOf('admission-refused', (source) async {
      await seedConnectedLibrary(source, key: 'backup');
    });

    // A separate exclusive owner prevents this restore from
    // acquiring local-write admission.
    final exclusiveEntered = Completer<void>();
    final releaseExclusive = Completer<void>();

    final blocker = target.mutationCoordinator.runExclusiveRestore(() async {
      exclusiveEntered.complete();
      await releaseExclusive.future;
    });

    await exclusiveEntered.future;

    try {
      await expectLater(
        orchestrator().restore(backup),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      // Restore must not leave a persisted restoring hold behind.
      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(await syncAllowed(), isTrue);
      expect(gate.isRestoreActive, isFalse);

      // The original local library must remain intact.
      final songs = await db.query(DatabaseTables.songs);
      expect(songs.map((row) => row['id']), contains('song-local'));

      await expectNoSessionLeftovers();
    } finally {
      releaseExclusive.complete();
      await blocker;
    }

    expect(target.mutationCoordinator.isRestoreRequested, isFalse);
    expect(target.mutationCoordinator.activeMutations, 0);

    // Local database transactions become available again.
    await target.transaction((transaction) async {
      final rows = await transaction.rawQuery('SELECT 1 AS value');
      expect(rows.single['value'], 1);
    });
  });
  test('local admission drain timeout restores sync hold', () async {
    // Install a short-timeout coordinator before opening the target DB.
    await target.close();

    target = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path.join(root.path, 'target.db'),
      mutationCoordinator: LibraryMutationCoordinator(
        drainTimeout: const Duration(milliseconds: 200),
      ),
    );

    final db = await target.database;
    await seedConnectedLibrary(db, key: 'local');

    final backup = await backupOf('admission-timeout', (source) async {
      await seedConnectedLibrary(source, key: 'backup');
    });

    final mutationEntered = Completer<void>();
    final releaseMutation = Completer<void>();

    // Register a local mutation without taking a SQLite lock.
    // This allows preflight to finish and isolates coordinator draining.
    final activeMutation = target.mutationCoordinator.runMutation(() async {
      mutationEntered.complete();
      await releaseMutation.future;
    });

    await mutationEntered.future;

    try {
      await expectLater(
        orchestrator().restore(backup),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect(await holdState(), isA<NoRecoverySyncHold>());
      expect(await syncAllowed(), isTrue);
      expect(gate.isRestoreActive, isFalse);

      expect(
        (await db.query(DatabaseTables.songs)).map((row) => row['id']),
        contains('song-local'),
      );

      expect(target.mutationCoordinator.isRestoreRequested, isFalse);
      expect(target.mutationCoordinator.activeMutations, 1);

      await expectNoSessionLeftovers();
    } finally {
      releaseMutation.complete();
      await activeMutation;
    }

    expect(target.mutationCoordinator.activeMutations, 0);

    await target.transaction((transaction) async {
      final rows = await transaction.rawQuery('SELECT 1 AS value');
      expect(rows.single['value'], 1);
    });

    await target.mutationCoordinator.runExclusiveRestore(() async {
      expect(target.mutationCoordinator.activeMutations, 0);
    });
  });
  group('A07: progress observers cannot change the outcome', () {
    for (final failing in RestoreStage.values) {
      test('an observer throwing at ${failing.name}', () async {
        final db = await target.database;
        await seedConnectedLibrary(db, key: 'local');
        final cover = await sourceArtwork('cover.jpg', [6, 6]);
        final backup = await backupOf('observer', (db) async {
          await seedConnectedLibrary(db, key: 'a', artworkPath: cover.path);
        });

        final seen = <RestoreStage>[];
        final result = await orchestrator().restore(
          backup,
          onProgress: (stage) {
            seen.add(stage);
            if (stage == failing) throw StateError('observer failed');
          },
        );

        expect(seen, contains(failing));
        expect(result.backupId, 'observer');
        expect(result.safetyBackup, isNotNull);
        expect(
          result.cleanupWarnings,
          contains(allOf(contains(failing.name), contains('observer failed'))),
        );
        expect(
          (await db.query(DatabaseTables.songs)).map((row) => row['id']),
          ['song-a'],
        );
        expect(await holdState(), isA<NoRecoverySyncHold>());
        expect(await syncAllowed(), isTrue);
        expect(gate.isRestoreActive, isFalse);
        await expectNoSessionLeftovers();
      });
    }

    test('a committed cloud-linked restore stays held despite a throwing observer', () async {
      await bindAccount('user-1');
      await seedConnectedLibrary(
        await target.database,
        key: 'a',
        userId: 'user-1',
        songTitle: 'Before',
      );
      final backup = await backupOf('cloud-observer', (db) async {
        await seedConnectedLibrary(db, key: 'a', userId: 'user-1', songTitle: 'After');
      });

      final result = await orchestrator().restore(
        backup,
        onProgress: (stage) {
          if (stage == RestoreStage.assessingSync ||
              stage == RestoreStage.completed) {
            throw StateError('observer failed');
          }
        },
      );

      expect(result.syncHeld, isTrue);
      final song = (await (await target.database).query(
        DatabaseTables.songs,
      )).single;
      expect(song['title'], 'After');
      final state = await holdState() as ActiveRecoverySyncHold;
      expect(state.hold.phase, RecoverySyncHoldPhase.assessmentRequired);
      expect(await syncAllowed(), isFalse);
    });
  });
}
