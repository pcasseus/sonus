import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
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

    final root = await recoveryDirectory();
    await root.create(recursive: true);
    final database = await appDatabase.database;
    final sessionId = _generateSessionId();

    // Housekeeping from earlier interrupted operations.
    onProgress?.call(RestoreStage.preparing);
    await cleaner.clean(root);
    await journalRecovery.recover(database);

    onProgress?.call(RestoreStage.verifyingBackup);
    final contents = await verifier.verifyAndExtract(
      backupFile: backupFile,
      targetDirectory: Directory(
        path.join(root.path, '.sonus_restore_$sessionId'),
      ),
    );

    try {
      onProgress?.call(RestoreStage.checkingCompatibility);
      final preflight = await RestorePreflightService(
        appDatabase: appDatabase,
        storageProbe: storageProbe,
        storagePath: root.path,
      ).assess(contents);

      if (!preflight.canRestore) {
        throw RestoreBlockedException(preflight);
      }

      onProgress?.call(RestoreStage.pausingSync);

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
        return await _restoreWhileHeld(
          contents: contents,
          sessionId: sessionId,
          previousHold: previousHold,
          captureBaseline: captureBaseline,
          onProgress: onProgress,
        );
      } finally {
        gate.endRestore();
      }
    } finally {
      // Covers blocked and failed restores; a committed restore has
      // already removed it.
      if (await contents.directory.exists()) {
        await contents.directory.delete(recursive: true);
      }
    }
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
    void Function(RestoreStage stage)? onProgress,
  }) async {
    final database = await appDatabase.database;
    var stage = RestoreStage.planning;
    File? safetyBackup;
    RecoveryFingerprint? baseline;
    var hold = switch (await _holdStore.read()) {
      ActiveRecoverySyncHold(:final hold) => hold,
      _ => throw StateError('Recovery sync hold was not persisted.'),
    };

    try {
      // No sync run is active; capture the state before any change.
      baseline = await fingerprints.capture(database);

      if (captureBaseline) {
        hold = hold.copyWith(preRestore: baseline);
        await _holdStore.write(hold);
      }

      onProgress?.call(stage);
      final RestorePlan plan = await RestorePlanner(
        appDatabase: appDatabase,
      ).plan(contents);

      if (plan.requiresSafetyBackup) {
        stage = RestoreStage.creatingSafetyBackup;
        onProgress?.call(stage);
        safetyBackup = await _createSafetyBackup(sessionId);

        // Independently verify before anything is replaced.
        await verifier.verify(safetyBackup);
      }

      stage = RestoreStage.installingArtwork;
      onProgress?.call(stage);

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

      final installation = await installer.install(
        artwork: contents.artwork,
        localPathsById: localArtwork,
        journal: journal,
        journalStore: journalStore,
      );

      stage = RestoreStage.restoringDatabase;
      onProgress?.call(stage);

      await database.transaction((transaction) async {
        // The exact state this transaction replaces; used to verify a
        // rollback and, for a fresh hold, as the sync baseline.
        final before = await fingerprints.capture(transaction);
        baseline = before;

        if (captureBaseline) {
          hold = hold.copyWith(preRestore: before);
          await _holdStore.write(hold);
        }

        await executor.apply(
          transaction: transaction,
          backup: contents.backup,
          artworkPaths: installation.pathsByArtworkId,
        );
      });

      // Committed. Remaining steps must not undo or misreport it.
      final warnings = <String>[];

      try {
        if (await contents.directory.exists()) {
          await contents.directory.delete(recursive: true);
        }
        await journalStore.clear();
      } catch (error) {
        warnings.add('Temporary restore data could not be removed: $error');
      }

      stage = RestoreStage.assessingSync;
      onProgress?.call(stage);

      final syncAssessment = await _assessAfterRestore(hold);

      final status = statusStore;

      if (status != null) {
        try {
          final audio = await RecoveryAudioStatusService(
            appDatabase: appDatabase,
          ).status(sampleLimit: 0);

          await status.recordRestore(
            RecoveryRestoreRecord(
              backupId: contents.backup.manifest.backupId,
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

      onProgress?.call(RestoreStage.completed);

      return RestoreResult(
        backupId: contents.backup.manifest.backupId,
        plan: plan,
        safetyBackup: safetyBackup,
        artworkInstalled: installation.installed,
        artworkReused: installation.reused,
        syncAssessment: syncAssessment,
        cleanupWarnings: warnings,
      );
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
  }

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
