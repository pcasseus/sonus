import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';

Map<String, int> completeCounts() => {
  for (final entry in BackupCoverageContract.portableTables) entry.table: 0,
};

BackupManifest validManifest() => BackupManifest(
  backupId: 'backup-001',
  createdAtUtc: DateTime.utc(2026, 10, 21),
  databaseVersion: AppDatabase.databaseVersion,
  rowCounts: completeCounts(),
);

void main() {
  test('valid manifest round-trips through JSON', () {
    final original = validManifest();

    final decoded = BackupManifest.fromJson(original.toJson());

    expect(decoded.backupId, original.backupId);
    expect(decoded.databaseVersion, AppDatabase.databaseVersion);
    expect(decoded.formatVersion, BackupManifest.currentFormatVersion);
    expect(decoded.rowCounts, original.rowCounts);
    expect(decoded.totalRows, 0);
    expect(decoded.createdAtUtc.isUtc, isTrue);
  });

  test('rejects missing portable tables', () {
    final counts = completeCounts();
    counts.remove(counts.keys.first);

    expect(
      () => BackupManifest(
        backupId: 'backup-001',
        createdAtUtc: DateTime.utc(2026),
        databaseVersion: AppDatabase.databaseVersion,
        rowCounts: counts,
      ),
      throwsFormatException,
    );
  });

  test('rejects unsupported format versions', () {
    final json = validManifest().toJson();
    json['formatVersion'] = 999;

    expect(() => BackupManifest.fromJson(json), throwsFormatException);
  });

  test('rejects invalid row counts', () {
    final counts = completeCounts();
    counts[counts.keys.first] = -1;

    expect(
      () => BackupManifest(
        backupId: 'backup-001',
        createdAtUtc: DateTime.utc(2026),
        databaseVersion: AppDatabase.databaseVersion,
        rowCounts: counts,
      ),
      throwsFormatException,
    );
  });

  test('rejects non-UTC backup timestamps', () {
    final json = validManifest().toJson();
    json['createdAtUtc'] = '2026-10-21T12:00:00';

    expect(() => BackupManifest.fromJson(json), throwsFormatException);
  });

  test('rejects database versions newer than the application', () {
    final json = validManifest().toJson();
    json['databaseVersion'] = AppDatabase.databaseVersion + 1;

    expect(() => BackupManifest.fromJson(json), throwsFormatException);
  });

  test('manifest row counts cannot be modified', () {
    final manifest = validManifest();

    expect(() => manifest.rowCounts.clear(), throwsUnsupportedError);
  });
}
