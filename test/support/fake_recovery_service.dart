import 'dart:async';
import 'dart:io';

import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_overview.dart';
import 'package:sonus_next/features/recovery/application/models/restore_plan.dart';
import 'package:sonus_next/features/recovery/application/models/restore_preflight.dart';
import 'package:sonus_next/features/recovery/application/models/restore_result.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_audio_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_status_store.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';

RestorePreflight fakePreflight({
  List<RestoreBlocker> blockers = const [],
  bool cloudLinked = false,
  int? availableBytes = 1 << 30,
}) => RestorePreflight(
  blockers: blockers,
  backupId: 'backup-1',
  backupCreatedAtUtc: DateTime.utc(2026, 10, 20, 9),
  backupDatabaseVersion: 31,
  backupAccountIds: cloudLinked ? const {'user-1'} : const {},
  localAccountId: cloudLinked ? 'user-1' : null,
  pendingSyncItemCount: 0,
  hasCloudSyncState: cloudLinked,
  estimatedRequiredBytes: 1024,
  availableBytes: availableBytes,
);

RestorePlan fakePlan({int songs = 12, int removed = 3, int missingAudio = 12}) =>
    RestorePlan(
      backupId: 'backup-1',
      localPortableRowCount: removed,
      tables: [
        for (final coverage in BackupCoverageContract.portableTables)
          RestoreTableChange(
            table: coverage.table,
            added: coverage.table == 'songs' ? songs : 1,
            updated: 0,
            unchanged: 0,
            removed: coverage.table == 'songs' ? removed : 0,
          ),
      ],
      deviceImpact: RestoreDeviceImpact(
        mediaBindingsKept: 0,
        mediaBindingsRemoved: 0,
        importReviewsKept: 0,
        importReviewsRemoved: 0,
        songsWithoutAudio: missingAudio,
        artworkReused: 0,
        artworkInstalled: 1,
      ),
    );

RecoveryOverview fakeOverview({
  RecoveryHoldOverview hold = RecoveryHoldOverview.none,
  int missingAudio = 0,
  List<PrivateBackupFile> privateBackups = const [],
  RecoveryStatus history = const RecoveryStatus(),
}) => RecoveryOverview(
  history: history,
  audio: RecoveryAudioStatus(
    totalSongs: 20,
    songsWithoutAudio: missingAudio,
    sample: [
      for (var i = 0; i < missingAudio && i < 3; i++)
        MissingAudioSong(
          songId: 'song-$i',
          title: 'Song $i',
          artistName: 'Artist',
        ),
    ],
  ),
  hold: hold,
  privateBackups: privateBackups,
);

/// Scriptable [RecoveryService] that records every call.
class FakeRecoveryService implements RecoveryService {
  final calls = <String>[];

  RecoveryOverview overview = fakeOverview();
  Object? startupError;
  File? pickedBackup = File('/picked/backup.sonusbackup');
  String? pickedFolder = '/music';
  RestorePreview Function(File file)? onPreview;
  Future<RestoreResult> Function(File file)? onRestore;
  BackupCreationResult backupResult = const BackupCreationResult(
    backupId: 'new-backup',
    export: BackupExportResult(outcome: BackupExportOutcome.verified),
  );
  BackupExportResult copyResult = const BackupExportResult(
    outcome: BackupExportOutcome.verified,
  );
  Completer<void>? restoreGate;

  @override
  Future<void> runStartupCheck() async {
    calls.add('startup');
    if (startupError != null) throw startupError!;
  }

  @override
  Future<RecoveryOverview> loadOverview() async {
    calls.add('overview');
    return overview;
  }

  @override
  Future<BackupCreationResult> createAndExportBackup({
    void Function(BackupStage stage)? onStage,
  }) async {
    calls.add('backup');
    onStage?.call(BackupStage.exportingDatabase);
    return backupResult;
  }

  @override
  Future<BackupExportResult> exportPrivateBackup(
    PrivateBackupFile backup,
  ) async {
    calls.add('export-copy');
    return copyResult;
  }

  @override
  Future<File?> pickBackupFile() async {
    calls.add('pick-backup');
    return pickedBackup;
  }

  @override
  Future<RestorePreview> previewRestore(File backupFile) async {
    calls.add('preview');
    return onPreview?.call(backupFile) ??
        RestorePreview(
          backupFile: backupFile,
          preflight: fakePreflight(),
          plan: fakePlan(),
        );
  }

  @override
  Future<RestoreResult> restore(
    File backupFile, {
    void Function(RestoreStage stage)? onStage,
  }) async {
    calls.add('restore');
    onStage?.call(RestoreStage.restoringDatabase);
    await restoreGate?.future;

    final handler = onRestore;
    if (handler != null) return handler(backupFile);

    return RestoreResult(
      backupId: 'backup-1',
      plan: fakePlan(),
      safetyBackup: File('/private/safety.sonusbackup'),
      artworkInstalled: 1,
      artworkReused: 0,
      syncAssessment: RecoverySyncAssessment(
        findings: const [RecoverySyncFinding.cloudLibraryDiverged],
        divergedTables: const ['songs'],
      ),
      cleanupWarnings: const [],
    );
  }

  @override
  Future<String?> pickMusicFolder() async {
    calls.add('pick-folder');
    return pickedFolder;
  }

  @override
  Future<RecoveryRelinkResult> relinkFromFolder(String folder) async {
    calls.add('relink:$folder');
    return const RecoveryRelinkResult(
      filesScanned: 10,
      relinked: 7,
      unmatchedOrAlreadyLinked: 3,
      failed: 0,
      missingBefore: 12,
      missingAfter: 5,
    );
  }

  @override
  Future<RecoverySyncAssessment> recheckSyncHold() async {
    calls.add('recheck');
    return RecoverySyncAssessment(findings: const [], divergedTables: const []);
  }
}
