enum RecoverySyncHoldPhase {
  /// Restore changes may be in progress or were interrupted.
  restoring,

  /// The restore finished; cloud consistency has not been established.
  assessmentRequired,

  /// The restore failed and its rollback could not be fully verified.
  restoreFailed,
}

/// Content digests describing the device immediately before a restore.
class RecoveryFingerprint {
  RecoveryFingerprint({
    required Map<String, String> tableDigests,
    required this.artworkContentDigest,
  }) : tableDigests = Map.unmodifiable(tableDigests);

  /// One digest per table, plus portable-only variants for tables with
  /// device-local columns (see `RecoveryFingerprintService`).
  final Map<String, String> tableDigests;

  /// Digest of the bytes of every artwork file referenced by the library.
  final String artworkContentDigest;

  Map<String, Object> toJson() => {
    'tableDigests': tableDigests,
    'artworkContentDigest': artworkContentDigest,
  };

  static RecoveryFingerprint fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['tableDigests'] is! Map<String, dynamic> ||
        json['artworkContentDigest'] is! String) {
      throw const FormatException('Invalid recovery fingerprint.');
    }

    final digests = <String, String>{};

    for (final entry in (json['tableDigests'] as Map<String, dynamic>).entries) {
      if (entry.value is! String) {
        throw const FormatException('Invalid recovery fingerprint digest.');
      }

      digests[entry.key] = entry.value as String;
    }

    return RecoveryFingerprint(
      tableDigests: digests,
      artworkContentDigest: json['artworkContentDigest'] as String,
    );
  }
}

/// Persistent record that cloud synchronization is paused for recovery.
///
/// It is written before any restore change and survives restarts. While it
/// exists, synchronization is rejected without performing any work.
class RecoverySyncHold {
  RecoverySyncHold({
    required this.holdId,
    required this.backupId,
    required this.createdAtUtc,
    required this.phase,
    required Set<String> backupAccountIds,
    required this.preRestore,
  }) : backupAccountIds = Set.unmodifiable(backupAccountIds);

  static const int currentVersion = 1;

  final String holdId;
  final String backupId;
  final DateTime createdAtUtc;
  final RecoverySyncHoldPhase phase;

  /// Owners recorded in the restored listening history.
  final Set<String> backupAccountIds;

  /// State before the first restore since sync last ran. Null only if a
  /// restore was interrupted before the state could be captured.
  final RecoveryFingerprint? preRestore;

  RecoverySyncHold copyWith({
    String? backupId,
    RecoverySyncHoldPhase? phase,
    Set<String>? backupAccountIds,
    RecoveryFingerprint? preRestore,
  }) {
    return RecoverySyncHold(
      holdId: holdId,
      backupId: backupId ?? this.backupId,
      createdAtUtc: createdAtUtc,
      phase: phase ?? this.phase,
      backupAccountIds: backupAccountIds ?? this.backupAccountIds,
      preRestore: preRestore ?? this.preRestore,
    );
  }

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'holdId': holdId,
    'backupId': backupId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'phase': phase.name,
    'backupAccountIds': backupAccountIds.toList()..sort(),
    'preRestore': preRestore?.toJson(),
  };

  static RecoverySyncHold fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['version'] != currentVersion ||
        json['holdId'] is! String ||
        json['backupId'] is! String ||
        json['createdAtUtc'] is! String ||
        json['phase'] is! String ||
        json['backupAccountIds'] is! List) {
      throw const FormatException('Invalid recovery sync hold.');
    }

    final createdAt = DateTime.tryParse(json['createdAtUtc'] as String);
    final phase = RecoverySyncHoldPhase.values
        .where((value) => value.name == json['phase'])
        .firstOrNull;
    final accounts = json['backupAccountIds'] as List;

    if (createdAt == null ||
        !createdAt.isUtc ||
        phase == null ||
        accounts.any((id) => id is! String)) {
      throw const FormatException('Invalid recovery sync hold.');
    }

    return RecoverySyncHold(
      holdId: json['holdId'] as String,
      backupId: json['backupId'] as String,
      createdAtUtc: createdAt,
      phase: phase,
      backupAccountIds: accounts.cast<String>().toSet(),
      preRestore: json['preRestore'] == null
          ? null
          : RecoveryFingerprint.fromJson(json['preRestore']),
    );
  }
}

/// Result of reading the persisted hold.
sealed class RecoverySyncHoldState {
  const RecoverySyncHoldState();
}

class NoRecoverySyncHold extends RecoverySyncHoldState {
  const NoRecoverySyncHold();
}

class ActiveRecoverySyncHold extends RecoverySyncHoldState {
  const ActiveRecoverySyncHold(this.hold);

  final RecoverySyncHold hold;
}

/// A hold file exists but cannot be trusted; sync stays paused.
class UnreadableRecoverySyncHold extends RecoverySyncHoldState {
  const UnreadableRecoverySyncHold(this.rawContent);

  final String? rawContent;
}
