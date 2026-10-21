import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../models/recovery_sync_hold.dart';
import 'recovery_fingerprint_service.dart';

enum RecoverySyncFinding {
  /// The persisted hold cannot be read, so nothing can be established.
  holdUnreadable,

  /// The pre-restore state was never captured (interrupted early).
  preRestoreStateMissing,

  /// Account binding or synchronization progress changed during recovery.
  syncStateChanged,

  /// The backup's history belongs to an account this device is not
  /// bound to, or the device has no account binding to confirm it.
  accountUnconfirmed,

  /// Library content represented in the cloud now differs from what the
  /// cloud sync state was built against. Pulling could overwrite restored
  /// data, and restored changes would not upload.
  cloudLibraryDiverged,

  /// Artwork bytes behind cloud-represented artwork changed.
  cloudArtworkDiverged,
}

class RecoverySyncAssessment {
  RecoverySyncAssessment({
    required List<RecoverySyncFinding> findings,
    required List<String> divergedTables,
  }) : findings = List.unmodifiable(findings),
       divergedTables = List.unmodifiable(divergedTables);

  final List<RecoverySyncFinding> findings;

  /// Cloud-represented tables whose content changed.
  final List<String> divergedTables;

  /// Consistency is proven only when there is nothing to report.
  bool get isConclusivelyConsistent => findings.isEmpty;
}

/// Determines whether synchronization may resume after a restore.
///
/// Consistency is concluded only by full-content comparison against the
/// state the existing cloud sync data was built for: either nothing that
/// sync represents has changed, or the device has no cloud association at
/// all. Identity matches alone never count as consistency.
class RecoverySyncAssessmentService {
  const RecoverySyncAssessmentService({
    this.fingerprints = const RecoveryFingerprintService(),
  });

  final RecoveryFingerprintService fingerprints;

  Future<RecoverySyncAssessment> assess({
    required RecoverySyncHoldState state,
    required DatabaseExecutor executor,
  }) async {
    final RecoverySyncHold hold;

    switch (state) {
      case NoRecoverySyncHold():
        return RecoverySyncAssessment(findings: const [], divergedTables: const []);
      case UnreadableRecoverySyncHold():
        return RecoverySyncAssessment(
          findings: const [RecoverySyncFinding.holdUnreadable],
          divergedTables: const [],
        );
      case ActiveRecoverySyncHold(hold: final active):
        hold = active;
    }

    final before = hold.preRestore;

    if (before == null) {
      return RecoverySyncAssessment(
        findings: const [RecoverySyncFinding.preRestoreStateMissing],
        divergedTables: const [],
      );
    }

    final now = await fingerprints.capture(executor);
    final findings = <RecoverySyncFinding>[];

    final syncChanged = RecoveryFingerprintService.syncStateTables.any(
      (table) => before.tableDigests[table] != now.tableDigests[table],
    );

    if (syncChanged) {
      findings.add(RecoverySyncFinding.syncStateChanged);
    }

    final binding = await executor.query(
      DatabaseTables.localAccountBinding,
      columns: ['user_id'],
    );
    final boundUserId = binding.isEmpty
        ? null
        : binding.single['user_id'] as String?;

    if (hold.backupAccountIds.isNotEmpty &&
        (boundUserId == null ||
            hold.backupAccountIds.length != 1 ||
            hold.backupAccountIds.single != boundUserId)) {
      findings.add(RecoverySyncFinding.accountUnconfirmed);
    }

    final diverged = [
      for (final table in RecoveryFingerprintService.cloudRepresentedTables)
        if (before.tableDigests[RecoveryFingerprintService.cloudDigestKey(
              table,
            )] !=
            now.tableDigests[RecoveryFingerprintService.cloudDigestKey(table)])
          table,
    ];

    final artworkChanged =
        before.artworkContentDigest != now.artworkContentDigest;

    // Divergence only matters if any cloud association exists or existed.
    final cloudAssociated =
        _hasCloudState(before) ||
        _hasCloudState(now) ||
        hold.backupAccountIds.isNotEmpty;

    if (cloudAssociated && diverged.isNotEmpty) {
      findings.add(RecoverySyncFinding.cloudLibraryDiverged);
    }

    if (cloudAssociated && artworkChanged) {
      findings.add(RecoverySyncFinding.cloudArtworkDiverged);
    }

    return RecoverySyncAssessment(
      findings: findings,
      divergedTables: cloudAssociated ? diverged : const [],
    );
  }

  bool _hasCloudState(RecoveryFingerprint fingerprint) {
    final empty = RecoveryFingerprintService.emptyTableDigest;

    return RecoveryFingerprintService.syncStateTables.any(
      (table) => (fingerprint.tableDigests[table] ?? empty) != empty,
    );
  }
}
