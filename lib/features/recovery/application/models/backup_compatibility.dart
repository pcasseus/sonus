import 'backup_manifest.dart';

/// Backup versions this build can restore.
abstract final class BackupCompatibility {
  /// Database versions whose portable tables match the current schema
  /// column for column.
  ///
  /// Migrations 32 and 33 only added internal sync tables, so backups from
  /// 31 onward restore unchanged. Each entry must be proven by a migration
  /// test before it is added; the schema validator still checks every
  /// payload against the local columns. Listed explicitly so a schema
  /// bump fails the compatibility tests until this set is reviewed.
  static const restorableDatabaseVersions = {31, 32, 33};

  static bool canRestore(BackupManifest manifest) =>
      manifest.formatVersion == BackupManifest.currentFormatVersion &&
      restorableDatabaseVersions.contains(manifest.databaseVersion);
}
