import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../artwork/data/services/file_system_artwork_managed_storage.dart';
import '../models/recovery_overview.dart';
import '../models/recovery_sync_hold.dart';
import '../models/restore_result.dart';
import 'backup_archive_verifier.dart';
import 'backup_document_exporter.dart';
import 'recovery_audio_service.dart';
import 'recovery_status_store.dart';
import 'recovery_sync_assessment_service.dart';
import 'recovery_sync_gate.dart';
import 'recovery_sync_hold_store.dart';
import 'restore_planner.dart';
import 'restore_preflight_service.dart';
import 'restored_artwork_installer.dart';
import 'sonus_backup_orchestrator.dart';
import 'sonus_restore_orchestrator.dart';
import 'sqlite_backup_exporter.dart';
import 'storage_space_probe.dart';
import 'verified_backup_publisher.dart';

/// Picks files and folders for recovery (platform dialogs).
abstract interface class RecoveryFilePicker {
  Future<File?> pickBackupFile();

  /// Returns a folder path, or an Android tree URI.
  Future<String?> pickMusicFolder();
}

typedef RelinkFolder = Future<RecoveryRelinkResult> Function(String folder);

/// Everything the Backup & Restore screens can ask of recovery.
abstract interface class RecoveryService {
  Future<void> runStartupCheck();

  Future<RecoveryOverview> loadOverview();

  Future<BackupCreationResult> createAndExportBackup({
    void Function(BackupStage stage)? onStage,
  });

  Future<BackupExportResult> exportPrivateBackup(PrivateBackupFile backup);

  Future<File?> pickBackupFile();

  Future<RestorePreview> previewRestore(File backupFile);

  Future<RestoreResult> restore(
    File backupFile, {
    void Function(RestoreStage stage)? onStage,
  });

  Future<String?> pickMusicFolder();

  Future<RecoveryRelinkResult> relinkFromFolder(String folder);

  Future<RecoverySyncAssessment> recheckSyncHold();
}

class DefaultRecoveryService implements RecoveryService {
  DefaultRecoveryService({
    required this.appDatabase,
    required this.gate,
    required this.recoveryDirectory,
    required this.artworkDirectory,
    required this.supportDirectory,
    required this.picker,
    required this.stopPlayback,
    required this.relink,
    this.exporter = const BackupDocumentExporter(),
    this.publisher = const VerifiedBackupPublisher(),
    this.storageProbe = const PlatformStorageSpaceProbe(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase appDatabase;
  final RecoverySyncGate gate;
  final RecoveryDirectoryProvider recoveryDirectory;
  final RecoveryDirectoryProvider artworkDirectory;
  final RecoveryDirectoryProvider supportDirectory;
  final RecoveryFilePicker picker;
  final Future<void> Function() stopPlayback;
  final RelinkFolder relink;
  final BackupDocumentExporter exporter;
  final VerifiedBackupPublisher publisher;
  final StorageSpaceProbe? storageProbe;
  final DateTime Function() _now;

  static const _verifier = BackupArchiveVerifier();

  RecoveryStatusStore get statusStore =>
      RecoveryStatusStore(directory: recoveryDirectory);

  SonusRestoreOrchestrator get _restorer => SonusRestoreOrchestrator(
    appDatabase: appDatabase,
    gate: gate,
    recoveryDirectory: recoveryDirectory,
    artworkDirectory: artworkDirectory,
    storageProbe: storageProbe,
    statusStore: statusStore,
    installer: RestoredArtworkInstaller(
      storageFactory: (fileId) => FileSystemArtworkManagedStorage(
        applicationSupportDirectoryProvider: supportDirectory,
        fileIdGenerator: fileId,
      ),
    ),
    safetyBackupWriter: (destination) => SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(appDatabase: appDatabase),
      publisher: publisher,
    ).createBackup(destination: destination),
    now: _now,
  );

  @override
  Future<void> runStartupCheck() =>
      gate.runStartupCheck(() => _restorer.reassessSyncHold());

  @override
  Future<RecoverySyncAssessment> recheckSyncHold() =>
      _restorer.reassessSyncHold();

  @override
  Future<RecoveryOverview> loadOverview() async {
    return RecoveryOverview(
      history: await statusStore.read(),
      audio: await RecoveryAudioStatusService(
        appDatabase: appDatabase,
      ).status(sampleLimit: 25),
      hold: await _holdOverview(),
      privateBackups: await _privateBackups(),
    );
  }

  Future<RecoveryHoldOverview> _holdOverview() async {
    final pending = gate.requiresStartupCheck && !gate.isStartupCheckComplete;
    final failed = gate.hasStartupCheckFailed;
    final state = await gate.holdStore.read();

    switch (state) {
      case NoRecoverySyncHold():
        return RecoveryHoldOverview(
          active: false,
          startupCheckPending: pending && !failed,
          startupCheckFailed: failed,
        );
      case UnreadableRecoverySyncHold():
        return RecoveryHoldOverview(
          active: true,
          unreadable: true,
          findings: const [RecoverySyncFinding.holdUnreadable],
          startupCheckPending: pending && !failed,
          startupCheckFailed: failed,
        );
      case ActiveRecoverySyncHold(:final hold):
        // Read-only: explaining the hold never releases it.
        final assessment = await const RecoverySyncAssessmentService().assess(
          state: state,
          executor: await appDatabase.database,
        );

        return RecoveryHoldOverview(
          active: true,
          phase: hold.phase,
          backupId: hold.backupId,
          since: hold.createdAtUtc,
          findings: assessment.findings,
          divergedTables: assessment.divergedTables,
          startupCheckPending: pending && !failed,
          startupCheckFailed: failed,
        );
    }
  }

  Future<List<PrivateBackupFile>> _privateBackups() async {
    final root = await recoveryDirectory();
    final found = <PrivateBackupFile>[];

    for (final (folder, kind) in [
      ('safety', PrivateBackupKind.safetyBackup),
      ('backups', PrivateBackupKind.unverifiedExportCopy),
    ]) {
      final directory = Directory(path.join(root.path, folder));

      if (!await directory.exists()) continue;

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.sonusbackup')) {
          continue;
        }

        final stat = await entity.stat();
        found.add(
          PrivateBackupFile(
            file: entity,
            kind: kind,
            byteLength: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
    }

    found.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return found;
  }

  @override
  Future<BackupCreationResult> createAndExportBackup({
    void Function(BackupStage stage)? onStage,
  }) async {
    final backupId = const Uuid().v4();
    final createdAt = _now().toUtc();
    final directory = Directory(
      path.join((await recoveryDirectory()).path, 'backups'),
    );
    await directory.create(recursive: true);

    final stamp = createdAt
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final name = 'sonus-backup-$stamp.sonusbackup';

    final backup = await SonusBackupOrchestrator(
      exporter: SqliteBackupExporter(
        appDatabase: appDatabase,
        generateId: () => backupId,
        now: () => createdAt,
      ),
      publisher: publisher,
    ).createBackup(
      destination: File(path.join(directory.path, name)),
      onProgress: onStage,
    );

    final export = await exporter.export(source: backup, suggestedName: name);

    switch (export.outcome) {
      case BackupExportOutcome.verified:
        await statusStore.recordBackup(
          RecoveryBackupRecord(
            backupId: backupId,
            createdAtUtc: createdAt,
            exportVerified: true,
          ),
        );
        // The verified off-device copy is the backup; drop the staging copy.
        await backup.delete();
        return BackupCreationResult(backupId: backupId, export: export);
      case BackupExportOutcome.cancelled:
        await backup.delete();
        return BackupCreationResult(backupId: backupId, export: export);
      case BackupExportOutcome.writtenUnverified:
      case BackupExportOutcome.failed:
        // Never leave the user without a verified copy somewhere.
        return BackupCreationResult(
          backupId: backupId,
          export: export,
          privateCopy: backup,
        );
    }
  }

  @override
  Future<BackupExportResult> exportPrivateBackup(PrivateBackupFile backup) =>
      // The private file is always kept; exporting only adds a copy.
      exporter.export(
        source: backup.file,
        suggestedName: path.basename(backup.file.path),
      );

  @override
  Future<File?> pickBackupFile() => picker.pickBackupFile();

  @override
  Future<RestorePreview> previewRestore(File backupFile) async {
    final root = await recoveryDirectory();
    await root.create(recursive: true);

    final contents = await _verifier.verifyAndExtract(
      backupFile: backupFile,
      targetDirectory: Directory(
        path.join(
          root.path,
          '.sonus_restore_preview_${const Uuid().v4().replaceAll('-', '')}',
        ),
      ),
    );

    try {
      final preflight = await RestorePreflightService(
        appDatabase: appDatabase,
        storageProbe: storageProbe,
        storagePath: root.path,
      ).assess(contents);

      final plan = preflight.canRestore
          ? await RestorePlanner(appDatabase: appDatabase).plan(contents)
          : null;

      return RestorePreview(
        backupFile: backupFile,
        preflight: preflight,
        plan: plan,
      );
    } finally {
      if (await contents.directory.exists()) {
        await contents.directory.delete(recursive: true);
      }
    }
  }

  @override
  Future<RestoreResult> restore(
    File backupFile, {
    void Function(RestoreStage stage)? onStage,
  }) async {
    await stopPlayback();

    // Every check runs again: the backup and device may have changed
    // since the preview.
    return _restorer.restore(backupFile, onProgress: onStage);
  }

  @override
  Future<String?> pickMusicFolder() => picker.pickMusicFolder();

  @override
  Future<RecoveryRelinkResult> relinkFromFolder(String folder) =>
      relink(folder);
}
