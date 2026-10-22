import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/recovery_overview.dart';
import '../models/restore_result.dart';
import '../services/backup_document_exporter.dart';
import '../services/recovery_audio_service.dart';
import '../services/recovery_service.dart';
import '../services/sonus_backup_orchestrator.dart';

enum RecoveryOperation {
  idle,
  checkingRecovery,
  backingUp,
  exportingCopy,
  preparingRestore,
  restoring,
  relinking,
}

/// State for the Backup & Restore screens.
///
/// Runs one operation at a time. A restore only starts from a successful
/// preview and an explicit acknowledgement; there is no way to bypass the
/// recovery sync hold from here.
class BackupRestoreController extends ChangeNotifier {
  BackupRestoreController({required this.service, this.onSyncMayResume});

  final RecoveryService service;

  /// Called when the startup check or a re-check leaves sync unpaused.
  final void Function()? onSyncMayResume;

  RecoveryOverview? _overview;
  Object? _overviewError;
  Object? _startupError;
  bool _loading = false;

  RecoveryOperation _operation = RecoveryOperation.idle;
  BackupStage? _backupStage;
  RestoreStage? _restoreStage;

  BackupCreationResult? _backupResult;
  BackupExportResult? _copyExportResult;
  RestorePreview? _preview;
  RestoreResult? _restoreResult;
  RecoveryRelinkResult? _relinkResult;
  Object? _operationError;
  bool _disposed = false;

  RecoveryOverview? get overview => _overview;
  Object? get overviewError => _overviewError;
  Object? get startupError => _startupError;
  bool get isLoading => _loading;

  RecoveryOperation get operation => _operation;
  bool get isBusy => _operation != RecoveryOperation.idle;
  BackupStage? get backupStage => _backupStage;
  RestoreStage? get restoreStage => _restoreStage;

  BackupCreationResult? get backupResult => _backupResult;
  BackupExportResult? get copyExportResult => _copyExportResult;
  RestorePreview? get preview => _preview;
  RestoreResult? get restoreResult => _restoreResult;
  RecoveryRelinkResult? get relinkResult => _relinkResult;
  Object? get operationError => _operationError;

  /// Runs the interrupted-restore check before anything else. Sync stays
  /// blocked by the gate if it fails.
  Future<void> initialize() async {
    await _run(RecoveryOperation.checkingRecovery, () async {
      try {
        await service.runStartupCheck();
        _startupError = null;
      } catch (error) {
        _startupError = error;
      }

      await _loadOverview();
    }, reportErrors: false);

    _notifyIfSyncMayResume();
  }

  Future<void> refresh() => _loadOverview();

  Future<void> createBackup() => _run(RecoveryOperation.backingUp, () async {
    _backupResult = null;
    _backupResult = await service.createAndExportBackup(
      onStage: (stage) {
        _backupStage = stage;
        _notify();
      },
    );
    await _loadOverview();
  });

  Future<void> exportPrivateBackup(PrivateBackupFile backup) =>
      _run(RecoveryOperation.exportingCopy, () async {
        _copyExportResult = null;
        _copyExportResult = await service.exportPrivateBackup(backup);
      });

  /// Lets the user pick a backup file and shows what restoring it would do.
  Future<void> chooseBackupToRestore() =>
      _run(RecoveryOperation.preparingRestore, () async {
        _preview = null;
        final file = await service.pickBackupFile();

        if (file == null) return;

        _preview = await service.previewRestore(file);
      });

  Future<void> previewBackup(File file) =>
      _run(RecoveryOperation.preparingRestore, () async {
        _preview = null;
        _preview = await service.previewRestore(file);
      });

  void cancelRestore() {
    if (isBusy) return;

    _preview = null;
    _operationError = null;
    _notify();
  }

  /// Replaces the library with the previewed backup. [acknowledged] must
  /// reflect the user's explicit confirmation.
  Future<void> confirmRestore({required bool acknowledged}) async {
    final preview = _preview;

    if (!acknowledged || preview == null || !preview.canRestore) {
      throw StateError('Restore requires a valid preview and confirmation.');
    }

    await _run(RecoveryOperation.restoring, () async {
      _restoreResult = await service.restore(
        preview.backupFile,
        onStage: (stage) {
          _restoreStage = stage;
          _notify();
        },
      );
      _preview = null;
    });

    if (_restoreResult == null) {
      // Failed or blocked: show the current state (including any hold).
      await _loadOverview();
    }
  }

  Future<void> relinkAudio() => _run(RecoveryOperation.relinking, () async {
    _relinkResult = null;
    final folder = await service.pickMusicFolder();

    if (folder == null) return;

    _relinkResult = await service.relinkFromFolder(folder);
    await _loadOverview();
  });

  /// Re-evaluates the sync hold. It is released only when consistency is
  /// conclusively established.
  Future<void> recheckSyncHold() async {
    await _run(RecoveryOperation.checkingRecovery, () async {
      try {
        await service.runStartupCheck();
        _startupError = null;
      } catch (error) {
        _startupError = error;
      }

      await service.recheckSyncHold();
      await _loadOverview();
    });

    _notifyIfSyncMayResume();
  }

  void dismissResults() {
    if (isBusy) return;

    _backupResult = null;
    _copyExportResult = null;
    _relinkResult = null;
    _operationError = null;
    _notify();
  }

  Future<void> _loadOverview() async {
    _loading = true;
    _notify();

    try {
      _overview = await service.loadOverview();
      _overviewError = null;
    } catch (error) {
      _overviewError = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> _run(
    RecoveryOperation operation,
    Future<void> Function() body, {
    bool reportErrors = true,
  }) async {
    if (isBusy) return;

    _operation = operation;
    _operationError = null;
    _backupStage = null;
    _restoreStage = null;
    _notify();

    try {
      await body();
    } catch (error) {
      if (reportErrors) _operationError = error;
    } finally {
      _operation = RecoveryOperation.idle;
      _notify();
    }
  }

  void _notifyIfSyncMayResume() {
    final hold = _overview?.hold;

    if (_startupError == null && hold != null && !hold.pausesSync) {
      onSyncMayResume?.call();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
