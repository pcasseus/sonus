import 'backup_manifest.dart';

/// Backup versions this build can restore.
abstract final class BackupCompatibility {
  /// Database versions whose portable tables match the current schema
  /// column for column.
  ///
  /// Migrations 32 and 33 only added internal sync tables, 34 only
  /// device-local organization tables, 35 only the device-local crop table,
  /// 36 only widened a check on chart Moments, 37 only added an internal
  /// sync table, 38 only added nullable release-format columns to the
  /// optional classification table (older rows restore with no format)
  /// and 39 only added the nullable release-date precision to editions
  /// (older rows restore without one, then imported year-only dates are
  /// marked again from their provenance), so backups from 31 onward
  /// restore unchanged. Each entry must be proven by a migration test
  /// before it is added; the schema validator still checks every payload
  /// against the local columns. Listed explicitly so a schema bump fails
  /// the compatibility tests until this set is reviewed.
  static const restorableDatabaseVersions = {
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
  };

  static bool canRestore(BackupManifest manifest) =>
      manifest.formatVersion == BackupManifest.currentFormatVersion &&
      restorableDatabaseVersions.contains(manifest.databaseVersion);
}
