import 'backup_manifest.dart';
import 'backup_table_coverage.dart';

class BackupDataPayload {
  BackupDataPayload({required Map<String, List<Map<String, Object?>>> tables})
    : tables = Map.unmodifiable({
        for (final entry in tables.entries)
          entry.key: List<Map<String, Object?>>.unmodifiable([
            for (final row in entry.value)
              Map<String, Object?>.unmodifiable(row),
          ]),
      }) {
    _validateStructure();
  }

  final Map<String, List<Map<String, Object?>>> tables;

  int get totalRows => tables.values.fold(0, (sum, rows) => sum + rows.length);

  void _validateStructure() {
    if (!BackupCoverageContract.isValidBackupTableSet(tables.keys.toSet())) {
      throw FormatException(
        'Backup payload must contain every required portable table, and '
        'only portable tables.',
      );
    }

    for (final entry in tables.entries) {
      for (final row in entry.value) {
        if (row.keys.any((key) => key.trim().isEmpty)) {
          throw FormatException('Backup row contains an empty column name.');
        }

        for (final value in row.values) {
          if (value != null &&
              value is! String &&
              value is! int &&
              value is! double) {
            throw FormatException(
              'Backup row contains an unsupported value type.',
            );
          }

          if (value is double && !value.isFinite) {
            throw FormatException('Backup row contains a non-finite number.');
          }
        }
      }
    }
  }

  void validateAgainst(BackupManifest manifest) {
    for (final entry in tables.entries) {
      if (manifest.rowCounts[entry.key] != entry.value.length) {
        throw FormatException(
          'Backup payload row count does not match manifest for '
          '${entry.key}.',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    for (final entry in tables.entries)
      entry.key: [
        for (final row in entry.value) Map<String, Object?>.from(row),
      ],
  };
}
