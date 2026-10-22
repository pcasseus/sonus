import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'atomic_state_file.dart';
import 'recovery_sync_hold_store.dart';

class RecoveryBackupRecord {
  const RecoveryBackupRecord({
    required this.backupId,
    required this.createdAtUtc,
    required this.exportVerified,
  });

  final String backupId;
  final DateTime createdAtUtc;

  /// The exported copy was read back and matched by SHA-256.
  final bool exportVerified;

  Map<String, Object> toJson() => {
    'backupId': backupId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'exportVerified': exportVerified,
  };

  static RecoveryBackupRecord fromJson(Map<String, dynamic> json) =>
      RecoveryBackupRecord(
        backupId: json['backupId'] as String,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
        exportVerified: json['exportVerified'] as bool,
      );
}

class RecoveryRestoreRecord {
  const RecoveryRestoreRecord({
    required this.backupId,
    required this.restoredAtUtc,
    required this.restoredRows,
    required this.songsWithoutAudio,
    required this.artworkInstalled,
    required this.artworkReused,
    required this.syncHeld,
    this.safetyBackupPath,
  });

  final String backupId;
  final DateTime restoredAtUtc;
  final int restoredRows;
  final int songsWithoutAudio;
  final int artworkInstalled;
  final int artworkReused;
  final bool syncHeld;
  final String? safetyBackupPath;

  Map<String, Object?> toJson() => {
    'backupId': backupId,
    'restoredAtUtc': restoredAtUtc.toIso8601String(),
    'restoredRows': restoredRows,
    'songsWithoutAudio': songsWithoutAudio,
    'artworkInstalled': artworkInstalled,
    'artworkReused': artworkReused,
    'syncHeld': syncHeld,
    'safetyBackupPath': safetyBackupPath,
  };

  static RecoveryRestoreRecord fromJson(Map<String, dynamic> json) =>
      RecoveryRestoreRecord(
        backupId: json['backupId'] as String,
        restoredAtUtc: DateTime.parse(json['restoredAtUtc'] as String),
        restoredRows: json['restoredRows'] as int,
        songsWithoutAudio: json['songsWithoutAudio'] as int,
        artworkInstalled: json['artworkInstalled'] as int,
        artworkReused: json['artworkReused'] as int,
        syncHeld: json['syncHeld'] as bool,
        safetyBackupPath: json['safetyBackupPath'] as String?,
      );
}

class RecoveryStatus {
  const RecoveryStatus({this.lastBackup, this.lastRestore});

  final RecoveryBackupRecord? lastBackup;
  final RecoveryRestoreRecord? lastRestore;
}

/// Display-only history of the latest backup and restore.
///
/// Never used for safety decisions (the sync hold and journal are), so an
/// unreadable file is treated as empty history.
class RecoveryStatusStore {
  const RecoveryStatusStore({
    required this.directory,
    this.stateFile = const AtomicStateFile(),
  });

  static const fileName = 'status.json';

  final RecoveryDirectoryProvider directory;
  final AtomicStateFile stateFile;

  Future<File> _file() async =>
      File(path.join((await directory()).path, fileName));

  Future<RecoveryStatus> read() async {
    final file = await _file();

    try {
      if (!await file.exists()) return const RecoveryStatus();

      final json = jsonDecode(await file.readAsString());

      if (json is! Map<String, dynamic>) return const RecoveryStatus();

      return RecoveryStatus(
        lastBackup: json['lastBackup'] is Map<String, dynamic>
            ? RecoveryBackupRecord.fromJson(json['lastBackup'])
            : null,
        lastRestore: json['lastRestore'] is Map<String, dynamic>
            ? RecoveryRestoreRecord.fromJson(json['lastRestore'])
            : null,
      );
    } catch (_) {
      return const RecoveryStatus();
    }
  }

  Future<void> recordBackup(RecoveryBackupRecord record) async {
    final current = await read();
    await _write(RecoveryStatus(lastBackup: record, lastRestore: current.lastRestore));
  }

  Future<void> recordRestore(RecoveryRestoreRecord record) async {
    final current = await read();
    await _write(RecoveryStatus(lastBackup: current.lastBackup, lastRestore: record));
  }

  Future<void> _write(RecoveryStatus status) async {
    await stateFile.writeString(
      await _file(),
      jsonEncode({
        'lastBackup': status.lastBackup?.toJson(),
        'lastRestore': status.lastRestore?.toJson(),
      }),
    );
  }
}
