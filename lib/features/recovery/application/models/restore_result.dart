import 'dart:io';

import '../services/recovery_sync_assessment_service.dart';
import 'restore_plan.dart';
import 'restore_preflight.dart';

enum RestoreStage {
  preparing,
  verifyingBackup,
  checkingCompatibility,
  pausingSync,
  planning,
  creatingSafetyBackup,
  installingArtwork,
  restoringDatabase,
  assessingSync,
  completed,
}

class RestoreResult {
  const RestoreResult({
    required this.backupId,
    required this.plan,
    required this.safetyBackup,
    required this.artworkInstalled,
    required this.artworkReused,
    required this.syncAssessment,
    required this.cleanupWarnings,
  });

  final String backupId;
  final RestorePlan plan;

  /// Verified backup of the library that was replaced, if it had data.
  final File? safetyBackup;

  final int artworkInstalled;
  final int artworkReused;

  final RecoverySyncAssessment syncAssessment;

  /// Sync stays paused unless consistency was conclusively established.
  bool get syncHeld => !syncAssessment.isConclusivelyConsistent;

  /// Non-fatal leftovers after a committed restore (e.g. a temporary
  /// folder that could not be removed yet).
  final List<String> cleanupWarnings;
}

/// The restore was refused before anything was changed.
class RestoreBlockedException implements Exception {
  const RestoreBlockedException(this.preflight);

  final RestorePreflight preflight;

  @override
  String toString() =>
      'RestoreBlockedException(${preflight.blockers.map((b) => b.name)})';
}

/// The restore failed; the database transaction was rolled back.
class RestoreFailedException implements Exception {
  const RestoreFailedException({
    required this.stage,
    required this.cause,
    required this.rollbackVerified,
    required this.syncHoldPreserved,
    this.safetyBackup,
  });

  final RestoreStage stage;
  final Object cause;

  /// The database and artwork were confirmed identical to their state
  /// before the restore, and every file the restore created was removed.
  final bool rollbackVerified;

  /// Sync remains paused because the rollback could not be verified.
  final bool syncHoldPreserved;

  final File? safetyBackup;

  @override
  String toString() =>
      'RestoreFailedException(stage: ${stage.name}, '
      'rollbackVerified: $rollbackVerified, cause: $cause)';
}
