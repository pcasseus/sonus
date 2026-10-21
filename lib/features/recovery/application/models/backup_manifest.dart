import '../../../../core/database/app_database.dart';
import 'backup_table_coverage.dart';

class BackupManifest {
  BackupManifest({
    required this.backupId,
    required this.createdAtUtc,
    required this.databaseVersion,
    required Map<String, int> rowCounts,
    this.formatVersion = currentFormatVersion,
  }) : rowCounts = Map.unmodifiable(rowCounts) {
    validate();
  }

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final int databaseVersion;
  final String backupId;
  final DateTime createdAtUtc;
  final Map<String, int> rowCounts;

  int get totalRows => rowCounts.values.fold(0, (sum, value) => sum + value);

  void validate() {
    if (formatVersion != currentFormatVersion) {
      throw FormatException('Unsupported backup format version.');
    }

    if (databaseVersion <= 0 || databaseVersion > AppDatabase.databaseVersion) {
      throw FormatException('Unsupported database schema version.');
    }

    if (backupId.trim().isEmpty) {
      throw FormatException('Backup identifier is missing.');
    }

    if (!createdAtUtc.isUtc) {
      throw FormatException('Backup timestamp must be UTC.');
    }

    final expectedTables = BackupCoverageContract.portableTables
        .map((entry) => entry.table)
        .toSet();

    if (rowCounts.keys.toSet().length != expectedTables.length ||
        !rowCounts.keys.toSet().containsAll(expectedTables)) {
      throw FormatException(
        'Backup manifest must describe every portable table.',
      );
    }

    if (rowCounts.values.any((count) => count < 0)) {
      throw FormatException('Backup row counts cannot be negative.');
    }
  }

  Map<String, Object> toJson() => {
    'formatVersion': formatVersion,
    'databaseVersion': databaseVersion,
    'backupId': backupId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'rowCounts': rowCounts,
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['formatVersion'];
    final databaseVersion = json['databaseVersion'];
    final backupId = json['backupId'];
    final timestamp = json['createdAtUtc'];
    final rawCounts = json['rowCounts'];

    if (formatVersion is! int ||
        databaseVersion is! int ||
        backupId is! String ||
        timestamp is! String ||
        rawCounts is! Map<String, dynamic>) {
      throw FormatException('Invalid backup manifest structure.');
    }

    final createdAt = DateTime.tryParse(timestamp);

    if (createdAt == null || !timestamp.endsWith('Z') || !createdAt.isUtc) {
      throw FormatException('Invalid UTC backup timestamp.');
    }

    final counts = <String, int>{};

    for (final entry in rawCounts.entries) {
      if (entry.value is! int) {
        throw FormatException('Invalid backup row count.');
      }

      counts[entry.key] = entry.value as int;
    }

    return BackupManifest(
      formatVersion: formatVersion,
      databaseVersion: databaseVersion,
      backupId: backupId,
      createdAtUtc: createdAt,
      rowCounts: counts,
    );
  }
}
