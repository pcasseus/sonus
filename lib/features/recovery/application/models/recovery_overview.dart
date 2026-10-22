import 'dart:io';

import '../services/backup_document_exporter.dart';
import '../services/recovery_audio_service.dart';
import '../services/recovery_status_store.dart';
import '../services/recovery_sync_assessment_service.dart';
import 'recovery_sync_hold.dart';
import 'restore_plan.dart';
import 'restore_preflight.dart';

enum PrivateBackupKind {
  /// Made automatically before a restore replaced the library.
  safetyBackup,

  /// A backup whose off-device copy could not be verified, kept here.
  unverifiedExportCopy,
}

/// A backup stored only inside Sonus's private app storage. It is lost if
/// the app is uninstalled or the device is reset; export it to keep it.
class PrivateBackupFile {
  const PrivateBackupFile({
    required this.file,
    required this.kind,
    required this.byteLength,
    required this.modifiedAt,
  });

  final File file;
  final PrivateBackupKind kind;
  final int byteLength;
  final DateTime modifiedAt;
}

class RecoveryHoldOverview {
  const RecoveryHoldOverview({
    required this.active,
    this.unreadable = false,
    this.phase,
    this.backupId,
    this.since,
    this.findings = const [],
    this.divergedTables = const [],
    this.startupCheckPending = false,
    this.startupCheckFailed = false,
  });

  static const none = RecoveryHoldOverview(active: false);

  /// Cloud sync is paused for recovery.
  final bool active;

  final bool unreadable;
  final RecoverySyncHoldPhase? phase;
  final String? backupId;
  final DateTime? since;

  /// What must be resolved before sync can resume.
  final List<RecoverySyncFinding> findings;
  final List<String> divergedTables;

  final bool startupCheckPending;
  final bool startupCheckFailed;

  bool get pausesSync => active || startupCheckPending || startupCheckFailed;
}

class RecoveryOverview {
  RecoveryOverview({
    required this.history,
    required this.audio,
    required this.hold,
    required List<PrivateBackupFile> privateBackups,
  }) : privateBackups = List.unmodifiable(privateBackups);

  final RecoveryStatus history;
  final RecoveryAudioStatus audio;
  final RecoveryHoldOverview hold;

  /// Newest first.
  final List<PrivateBackupFile> privateBackups;
}

class RestorePreview {
  const RestorePreview({
    required this.backupFile,
    required this.preflight,
    required this.plan,
  });

  final File backupFile;
  final RestorePreflight preflight;

  /// Null when the preflight blocks the restore.
  final RestorePlan? plan;

  bool get canRestore => preflight.canRestore && plan != null;
}

class BackupCreationResult {
  const BackupCreationResult({
    required this.backupId,
    required this.export,
    this.privateCopy,
  });

  final String backupId;
  final BackupExportResult export;

  /// Kept on this device when the off-device copy is not verified.
  final File? privateCopy;
}
