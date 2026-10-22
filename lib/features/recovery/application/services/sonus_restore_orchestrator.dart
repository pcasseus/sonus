import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../models/backup_table_coverage.dart';
import '../models/recovery_sync_hold.dart';
import '../models/restore_plan.dart';
import '../models/restore_preflight.dart';
import '../models/restore_result.dart';
import 'backup_archive_verifier.dart';
import 'backup_temporary_cleaner.dart';
import 'recovery_audio_service.dart';
import 'recovery_fingerprint_service.dart';
import 'recovery_status_store.dart';
import 'recovery_sync_assessment_service.dart';
import 'recovery_sync_gate.dart';
import 'recovery_sync_hold_store.dart';
import 'restore_journal_store.dart';
import 'restore_planner.dart';
import 'restore_preflight_service.dart';
import 'restored_artwork_installer.dart';
import 'sonus_backup_orchestrator.dart';
import 'sqlite_backup_exporter.dart';
import 'sqlite_restore_executor.dart';
import 'storage_space_probe.dart';

typedef SafetyBackupWriter = Future<File> Function(File destination);

/// Restores a Sonus backup as one recoverable operation.
///
/// Order: housekeeping → verify and extract → preflight → pause sync
/// (persisted hold, active runs drained) → plan → verified safety backup →
/// journaled artwork install → single SQLite transaction → sync assessment.
///
/// On failure the transaction rolls back, files this session created are
/// removed, and the rollback is verified by content before the previous
/// sync state is reinstated. If verification is not possible, sync stays
/// paused.
class SonusRestoreOrchestrator {
  SonusRestoreOrchestrator({
    required this.appDatabase,
    required this.gate,
    required this.recoveryDirectory,
    RecoveryDirectoryProvider? artworkDirectory,
    this._safetyBackupWriter,
    this.storageProbe = const PlatformStorageSpaceProbe(),
    this.verifier = const BackupArchiveVerifier(),
    this.installer = const RestoredArtworkInstaller(),
    this.executor = const SqliteRestoreExecutor(),
    this.fingerprints = const RecoveryFingerprintService(),
    this.assessment = const RecoverySyncAssessmentService(),
    this.cleaner = const BackupTemporaryCleaner(),
    this._journalRecovery,
    this.statusStore,
    DateTime Function()? now,
    String Function()? generateSessionId,
  }) : artworkDirectory = artworkDirectory ?? _applicationArtworkDirectory,
       _now = now ?? DateTime.now,
       _generateSessionId =
           generateSessionId ?? (() => const Uuid().v4().replaceAll('-', ''));

  final AppDatabase appDatabase;
  final RecoverySyncGate gate;
  final RecoveryDirectoryProvider recoveryDirectory;
  final RecoveryDirectoryProvider artworkDirectory;
  final StorageSpaceProbe? storageProbe;
  final BackupArchiveVerifier verifier;
  final RestoredArtworkInstaller installer;
  final SqliteRestoreExecutor executor;
  final RecoveryFingerprintService fingerprints;
  final RecoverySyncAssessmentService assessment;
  final BackupTemporaryCleaner cleaner;

  /// Optional display history of completed restores.
  final RecoveryStatusStore? statusStore;

  final SafetyBackupWriter? _safetyBackupWriter;
  final RestoreJournalRecovery? _journalRecovery;
  final DateTime Function() _now;
  final String Function() _generateSessionId;

  RecoverySyncHoldStore get _holdStore => gate.holdStore;

  RestoreJournalStore get journalStore =>
      RestoreJournalStore(directory: recoveryDirectory);

  RestoreJournalRecovery get journalRecovery =>
      _journalRecovery ??
      RestoreJournalRecovery(
        journalStore: journalStore,
        artworkDirectory: artworkDirectory,
      );

  static Future<Directory> _applicationArtworkDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'sonus', 'artwork'));
  }

  Future<RestoreResult> restore(
    File backupFile, {
    void Function(RestoreStage stage)? onProgress,
  }) async {
    if (gate.isRestoreActive) {
      throw const RecoveryGateUnavailable('A restore is already running.');
    }

    if (!gate.isStartupCheckComplete) {
      throw const RecoveryGateUnavailable(
        'The startup recovery check has not completed.',
      );
    }

    // Progress is observational: an observer that throws never changes
    // what the restore does or how its outcome is reported.
    final progressFailures = <String>[];

    void report(RestoreStage stage) {
      if (onProgress == null) return;

      try {
        onProgress(stage);
      } catch (error) {
        progressFailures.add(
          'A progress update (${stage.name}) failed: $error',
        );
      }
    }

    final root = await recoveryDirectory();
    await root.create(recursive: true);
    final database = await appDatabase.database;
    final sessionId = _generateSessionId();

    // Housekeeping from earlier interrupted operations.
    report(RestoreStage.preparing);
    await cleaner.clean(root);
    await journalRecovery.recover(database);

    report(RestoreStage.verifyingBackup);
    final contents = await verifier.verifyAndExtract(
      backupFile: backupFile,
      targetDirectory: Directory(
        path.join(root.path, '.sonus_restore_$sessionId'),
      ),
    );

    try {
      report(RestoreStage.checkingCompatibility);
      final preflightService = RestorePreflightService(
        appDatabase: appDatabase,
        storageProbe: storageProbe,
        storagePath: root.path,
      );
      final preflight = await preflightService.assess(contents);

      if (!preflight.canRestore) {
        throw RestoreBlockedException(preflight);
      }

      report(RestoreStage.pausingSync);

      // Only a device with no prior hold has a trustworthy baseline to
      // capture; an existing hold keeps the baseline from before its
      // restore, and an unreadable one is never given a baseline.
      var captureBaseline = false;

      final previousHold = await gate.beginRestore((previous) {
        switch (previous) {
          case ActiveRecoverySyncHold(:final hold):
            return hold.copyWith(
              backupId: preflight.backupId,
              phase: RecoverySyncHoldPhase.restoring,
              backupAccountIds: preflight.backupAccountIds,
            );
          case NoRecoverySyncHold():
            captureBaseline = true;
            return _newHold(sessionId, preflight.backupId, preflight);
          case UnreadableRecoverySyncHold():
            return _newHold(sessionId, preflight.backupId, preflight);
        }
      });

      try {
        // Sync runs that were active during the first check have drained
        // and new runs are rejected. Pending work, the account binding, or
        // free space may have changed meanwhile, so decide again before
        // anything is written. Nothing has changed yet, so a blocked
        // restore reinstates the previous hold unchanged.
        final current = await preflightService.assess(contents);

        if (!current.canRestore) {
          await _reinstateHold(previousHold);
          throw RestoreBlockedException(current);
        }

        return await _restoreWhileHeld(
          contents: contents,
          sessionId: sessionId,
          previousHold: previousHold,
          captureBaseline: captureBaseline,
          preflightService: preflightService,
          report: report,
          progressFailures: progressFailures,
        );
      } finally {
        gate.endRestore();
      }
    } finally {
      // Covers blocked and failed restores; a committed restore has
      // already removed it. A folder that cannot be removed now is left
      // for BackupTemporaryCleaner and must never replace the outcome.
      try {
        if (await contents.directory.exists()) {
          await contents.directory.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Puts back the hold state from before [RecoverySyncGate.beginRestore]
  /// when the restore stopped before changing anything. If that fails the
  /// restoring hold remains and sync stays paused until reassessed.
  Future<void> _reinstateHold(RecoverySyncHoldState previous) async {
    try {
      await _holdStore.restore(previous);
    } catch (_) {}
  }

  RecoverySyncHold _newHold(
    String sessionId,
    String backupId,
    RestorePreflight preflight,
  ) {
    return RecoverySyncHold(
      holdId: sessionId,
      backupId: backupId,
      createdAtUtc: _now().toUtc(),
      phase: RecoverySyncHoldPhase.restoring,
      backupAccountIds: preflight.backupAccountIds,
      preRestore: null,
    );
  }

  Future<RestoreResult> _restoreWhileHeld({
    required VerifiedBackupContents contents,
    required String sessionId,
    required RecoverySyncHoldState previousHold,
    required bool captureBaseline,
    required RestorePreflightService preflightService,
    required void Function(RestoreStage stage) report,
    required List<String> progressFailures,
  }) async {
    final database = await appDatabase.database;
    var stage = RestoreStage.planning;
    File? safetyBackup;
    RecoveryFingerprint? baseline;
    late final RestorePlan plan;
    late final RestoredArtworkInstallation installation;
    var hold = switch (await _holdStore.read()) {
      ActiveRecoverySyncHold(:final hold) => hold,
      _ => throw StateError('Recovery sync hold was not persisted.'),
    };

    // Everything up to and including the transaction is pre-commit: any
    // failure rolls back and is verified. Nothing after it may undo or
    // misreport the committed restore.
    try {
      // No sync run is active; capture the state before any change. The
      // safety backup below preserves exactly this state.
      final quiesced = await fingerprints.capture(database);
      baseline = quiesced;

      if (captureBaseline) {
        hold = hold.copyWith(preRestore: quiesced);
        await _holdStore.write(hold);
      }

      report(stage);
      plan = await RestorePlanner(appDatabase: appDatabase).plan(contents);

      if (plan.requiresSafetyBackup) {
        stage = RestoreStage.creatingSafetyBackup;
        report(stage);
        safetyBackup = await _createSafetyBackup(sessionId);

        // Independently verify before anything is replaced.
        await verifier.verify(safetyBackup);
      }

      stage = RestoreStage.installingArtwork;
      report(stage);

      final journal = RestoreJournal(
        sessionId: sessionId,
        extractionDirectory: contents.directory.path,
        reservedTokens: const [],
        createdFiles: const [],
      );
      await journalStore.write(journal);

      final localArtwork = {
        for (final row in await database.query(
          DatabaseTables.artworkAssets,
          columns: ['id', 'file_path'],
        ))
          row['id'] as String: row['file_path'] as String,
      };

      installation = await installer.install(
        artwork: contents.artwork,
        localPathsById: localArtwork,
        journal: journal,
        journalStore: journalStore,
      );

      stage = RestoreStage.restoringDatabase;
      report(stage);

      await database.transaction((transaction) async {
        // The exact state this transaction replaces; used to verify a
        // rollback and, for a fresh hold, as the sync baseline.
        final before = await fingerprints.capture(transaction);
        baseline = before;

        if (captureBaseline) {
          hold = hold.copyWith(preRestore: before);
          await _holdStore.write(hold);
        }

        // No other write can interleave from here until commit. Anything
        // that changed the library or sync state since sync quiesced (an
        // edit, an import, a new play, a sign-in) would be lost or left
        // out of the safety backup, so the restore is abandoned instead.
        final changed = _changedRestoreTables(quiesced, before);
        final recheck = await preflightService.assessWithin(
          transaction,
          contents,
        );

        if (changed.isNotEmpty || !recheck.canRestore) {
          throw RestoreConditionsChangedException(
            blockers: recheck.blockers,
            changedTables: changed,
          );
        }

        await executor.apply(
          transaction: transaction,
          backup: contents.backup,
          artworkPaths: installation.pathsByArtworkId,
        );
      });
    } catch (error) {
      if (error is RestoreFailedException) rethrow;

      final verified = await _cleanUpAndVerifyRollback(baseline);

      var holdPreserved = !verified;

      try {
        if (verified) {
          await _holdStore.restore(previousHold);
        } else {
          await _holdStore.write(
            hold.copyWith(phase: RecoverySyncHoldPhase.restoreFailed),
          );
        }
      } catch (_) {
        // The persisted restoring hold remains, so sync stays paused.
        holdPreserved = true;
      }

      throw RestoreFailedException(
        stage: stage,
        cause: error,
        rollbackVerified: verified,
        syncHoldPreserved: holdPreserved,
        safetyBackup: safetyBackup,
      );
    }

    return _completeCommittedRestore(
      contents: contents,
      hold: hold,
      plan: plan,
      installation: installation,
      safetyBackup: safetyBackup,
      report: report,
      progressFailures: progressFailures,
    );
  }

  /// Finishes a restore whose transaction has committed. It never throws:
  /// the database cannot be rolled back any more, so every later problem
  /// is reported as a warning on a successful result. The sync hold stays
  /// in force unless the assessment conclusively releases it.
  Future<RestoreResult> _completeCommittedRestore({
    required VerifiedBackupContents contents,
    required RecoverySyncHold hold,
    required RestorePlan plan,
    required RestoredArtworkInstallation installation,
    required File? safetyBackup,
    required void Function(RestoreStage stage) report,
    required List<String> progressFailures,
  }) async {
    final warnings = <String>[];
    final backupId = contents.backup.manifest.backupId;

    try {
      if (await contents.directory.exists()) {
        await contents.directory.delete(recursive: true);
      }
      await journalStore.clear();
    } catch (error) {
      warnings.add('Temporary restore data could not be removed: $error');
    }

    report(RestoreStage.assessingSync);

    RecoverySyncAssessment syncAssessment;

    try {
      syncAssessment = await _assessAfterRestore(hold);
    } catch (_) {
      // Unreachable in practice (_assessAfterRestore handles its own
      // failures); kept so a committed restore is never misreported.
      syncAssessment = RecoverySyncAssessment(
        findings: const [RecoverySyncFinding.preRestoreStateMissing],
        divergedTables: const [],
      );
    }

    final status = statusStore;

    if (status != null) {
      try {
        final audio = await RecoveryAudioStatusService(
          appDatabase: appDatabase,
        ).status(sampleLimit: 0);

        await status.recordRestore(
          RecoveryRestoreRecord(
            backupId: backupId,
            restoredAtUtc: _now().toUtc(),
            restoredRows: contents.backup.payload.totalRows,
            songsWithoutAudio: audio.songsWithoutAudio,
            artworkInstalled: installation.installed,
            artworkReused: installation.reused,
            syncHeld: !syncAssessment.isConclusivelyConsistent,
            safetyBackupPath: safetyBackup?.path,
          ),
        );
      } catch (error) {
        warnings.add('Restore history could not be saved: $error');
      }
    }

    report(RestoreStage.completed);

    return RestoreResult(
      backupId: backupId,
      plan: plan,
      safetyBackup: safetyBackup,
      artworkInstalled: installation.installed,
      artworkReused: installation.reused,
      syncAssessment: syncAssessment,
      cleanupWarnings: [...warnings, ...progressFailures],
    );
  }

  /// Portable library and sync-state tables, and referenced artwork
  /// content, that differ between [from] and [to].
  List<String> _changedRestoreTables(
    RecoveryFingerprint from,
    RecoveryFingerprint to,
  ) {
    final tables = {
      for (final coverage in BackupCoverageContract.portableTables)
        coverage.table,
      ...RecoveryFingerprintService.syncStateTables,
    };

    return [
      for (final table in tables.toList()..sort())
        if (from.tableDigests[table] != to.tableDigests[table]) table,
      if (from.artworkContentDigest != to.artworkContentDigest)
        artworkContentKey,
    ];
  }

  /// Reported in [RestoreConditionsChangedException.changedTables] when the
  /// content of referenced artwork files changed.
  static const artworkContentKey = 'artwork files';

  /// Removes this session's files and confirms that the database and
  /// artwork match [baseline] exactly. Returns false if anything cannot be
  /// confirmed.
  Future<bool> _cleanUpAndVerifyRollback(RecoveryFingerprint? baseline) async {
    try {
      final database = await appDatabase.database;
      final journal = await journalStore.read();

      if (journal != null) {
        await journalRecovery.discard(journal, database);

        for (final file in journal.createdFiles) {
          if (await FileSystemEntity.type(file, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
        }
      }

      if (baseline == null) {
        return false;
      }

      final after = await fingerprints.capture(database);

      if (!_sameFingerprint(baseline, after)) {
        return false;
      }

      await journalStore.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _sameFingerprint(RecoveryFingerprint a, RecoveryFingerprint b) {
    if (a.artworkContentDigest != b.artworkContentDigest ||
        a.tableDigests.length != b.tableDigests.length) {
      return false;
    }

    for (final entry in a.tableDigests.entries) {
      if (b.tableDigests[entry.key] != entry.value) return false;
    }

    return true;
  }

  Future<RecoverySyncAssessment> _assessAfterRestore(
    RecoverySyncHold hold,
  ) async {
    final database = await appDatabase.database;

    try {
      final result = await assessment.assess(
        state: ActiveRecoverySyncHold(hold),
        executor: database,
      );

      if (result.isConclusivelyConsistent) {
        await _holdStore.clear();
      } else {
        await _holdStore.write(
          hold.copyWith(phase: RecoverySyncHoldPhase.assessmentRequired),
        );
      }

      return result;
    } catch (_) {
      // Nothing could be established; the restoring hold stays in place.
      return RecoverySyncAssessment(
        findings: const [RecoverySyncFinding.preRestoreStateMissing],
        divergedTables: const [],
      );
    }
  }

  /// Recovers from an interrupted restore and re-evaluates a persisted
  /// hold, releasing it only if consistency is conclusively established.
  /// Intended for app start and for an explicit "check again" action.
  Future<RecoverySyncAssessment> reassessSyncHold() async {
    if (gate.isRestoreActive) {
      throw const RecoveryGateUnavailable('A restore is running.');
    }

    final database = await appDatabase.database;
    await journalRecovery.recover(database);

    final state = await _holdStore.read();
    final result = await assessment.assess(state: state, executor: database);

    if (state is ActiveRecoverySyncHold) {
      if (result.isConclusivelyConsistent) {
        await _holdStore.clear();
      } else if (state.hold.phase == RecoverySyncHoldPhase.restoring) {
        await _holdStore.write(
          state.hold.copyWith(phase: RecoverySyncHoldPhase.assessmentRequired),
        );
      }
    }

    return result;
  }

  Future<File> _createSafetyBackup(String sessionId) async {
    final directory = Directory(
      path.join((await recoveryDirectory()).path, 'safety'),
    );
    await directory.create(recursive: true);

    final stamp = _now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final destination = File(
      path.join(directory.path, 'pre-restore-$stamp-$sessionId.sonusbackup'),
    );

    final writer =
        _safetyBackupWriter ??
        (File target) => SonusBackupOrchestrator(
          exporter: SqliteBackupExporter(appDatabase: appDatabase),
        ).createBackup(destination: target);

    return writer(destination);
  }
}
