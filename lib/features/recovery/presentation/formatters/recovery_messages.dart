import '../../application/models/backup_failure.dart';
import '../../application/models/restore_preflight.dart';
import '../../application/models/restore_result.dart';
import '../../application/services/recovery_sync_assessment_service.dart';
import '../../application/services/recovery_sync_gate.dart';
import '../../application/services/sonus_backup_orchestrator.dart';
import '../../application/services/sqlite_restore_executor.dart';

abstract final class RecoveryMessages {
  static String finding(RecoverySyncFinding finding) => switch (finding) {
    RecoverySyncFinding.holdUnreadable =>
      'Sonus could not read its recovery record, so it cannot confirm that '
          'syncing is safe.',
    RecoverySyncFinding.preRestoreStateMissing =>
      'A restore was interrupted before Sonus recorded what your library '
          'looked like, so it cannot compare it with the cloud.',
    RecoverySyncFinding.syncStateChanged =>
      'Your account link or sync progress changed during recovery.',
    RecoverySyncFinding.accountUnconfirmed =>
      'The restored listening history belongs to an account this device is '
          'not signed in to, or the account could not be confirmed.',
    RecoverySyncFinding.cloudLibraryDiverged =>
      'Your restored library is different from the one your cloud account '
          'was last synced with. Syncing now could overwrite restored data or '
          'leave restored changes un-uploaded.',
    RecoverySyncFinding.cloudArtworkDiverged =>
      'Restored artwork differs from the artwork your cloud account knows.',
  };

  static String tableName(String table) => switch (table) {
    'artists' => 'Artists',
    'albums' => 'Albums',
    'album_editions' => 'Album editions',
    'songs' => 'Songs',
    'artwork_assets' => 'Artwork',
    'song_artist_credits' => 'Artist credits',
    'album_edition_tracks' => 'Track listings',
    'metadata_field_states' => 'Metadata details',
    _ => table,
  };

  static String blocker(RestoreBlocker blocker) => switch (blocker) {
    RestoreBlocker.incompatibleBackupVersion =>
      'This backup was created by a different version of Sonus and cannot be '
          'restored by this version.',
    RestoreBlocker.incompatibleLocalDatabase =>
      'This device\'s library database is not at the expected version.',
    RestoreBlocker.schemaMismatch =>
      'The backup\'s data does not match this version\'s library structure.',
    RestoreBlocker.multipleBackupAccounts =>
      'The backup contains listening history from more than one account.',
    RestoreBlocker.accountConflict =>
      'The backup belongs to a different Sonus account than this device.',
    RestoreBlocker.pendingSyncWork =>
      'Some changes on this device have not been synced to your cloud '
          'account yet. Let sync finish first so nothing is lost.',
    RestoreBlocker.insufficientStorage =>
      'There is not enough free storage on this device for a safe restore.',
    RestoreBlocker.storageCheckFailed =>
      'Sonus could not check the free storage on this device.',
  };

  static String backupStage(BackupStage stage) => switch (stage) {
    BackupStage.exportingDatabase => 'Reading your library…',
    BackupStage.collectingArtwork => 'Collecting artwork…',
    BackupStage.stagingArtwork => 'Copying artwork…',
    BackupStage.writingDocuments => 'Writing backup data…',
    BackupStage.packagingAndVerifying => 'Packaging and verifying…',
    BackupStage.published => 'Backup created',
  };

  static String restoreStage(RestoreStage stage) => switch (stage) {
    RestoreStage.preparing => 'Preparing…',
    RestoreStage.verifyingBackup => 'Verifying the backup…',
    RestoreStage.checkingCompatibility => 'Checking compatibility…',
    RestoreStage.pausingSync => 'Pausing cloud sync…',
    RestoreStage.planning => 'Planning the restore…',
    RestoreStage.creatingSafetyBackup =>
      'Saving a safety backup of your current library…',
    RestoreStage.installingArtwork => 'Installing artwork…',
    RestoreStage.restoringDatabase => 'Restoring your library…',
    RestoreStage.assessingSync => 'Checking cloud sync safety…',
    RestoreStage.completed => 'Restore complete',
  };

  static String error(Object error) {
    if (error is RestoreBlockedException) {
      return error.preflight.blockers.map(blocker).join(' ');
    }

    if (error is RestoreFailedException) {
      final base = switch (error.stage) {
        RestoreStage.creatingSafetyBackup =>
          'The safety backup of your current library could not be created, '
              'so nothing was restored.',
        _ => 'The restore could not be completed.',
      };

      final outcome = error.rollbackVerified
          ? ' Your library was left exactly as it was.'
          : ' Your library database was rolled back, but Sonus could not '
                'confirm every file was cleaned up, so cloud sync stays '
                'paused.';

      final cause = error.cause;
      final detail = cause is BackupException &&
              cause.code == BackupFailureCode.missingArtwork
          ? ' ${missingArtwork(cause.artworkIds.length)}'
          : '';

      return '$base$outcome$detail';
    }

    if (error is BackupException) {
      return switch (error.code) {
        BackupFailureCode.missingArtwork => missingArtwork(
          error.artworkIds.length,
        ),
        BackupFailureCode.invalidArtwork =>
          'Some artwork in your library is invalid, so the backup was not '
              'created.',
        BackupFailureCode.artworkChanged =>
          'Artwork changed while the backup was being made. Please try again.',
        BackupFailureCode.publicationFailed =>
          'The backup file could not be saved safely on this device.',
      };
    }

    if (error is RecoveryGateUnavailable) {
      return 'Please try again in a moment: ${error.message}';
    }

    if (error is RestoreIntegrityFailure) {
      return 'The restored data failed an integrity check, so nothing was '
          'changed.';
    }

    if (error is FormatException) {
      return 'This file is not a valid Sonus backup, or it is damaged.';
    }

    return 'Something went wrong. Nothing was changed.';
  }

  static String missingArtwork(int count) => count == 1
      ? 'One artwork file is missing from this device. Re-add or remove that '
            'artwork, then try again.'
      : '$count artwork files are missing from this device. Re-add or remove '
            'that artwork, then try again.';

  static String bytes(int value) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = value.toDouble();
    var unit = 0;

    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }

    return unit == 0
        ? '$value B'
        : '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
  }

  static String dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
