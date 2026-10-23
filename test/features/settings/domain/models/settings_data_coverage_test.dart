import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/settings/domain/models/settings_data_coverage.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  test('every backed-up or device-local table is described to users', () {
    // Adding a table to the backup contract without describing it here
    // would make Settings silently understate what a backup contains.
    for (final entry in BackupCoverageContract.tables) {
      if (entry.policy == BackupTablePolicy.internalState) {
        expect(
          SettingsDataCoverage.backupTableLabels,
          isNot(contains(entry.table)),
          reason: 'internal table ${entry.table} must not be shown',
        );
        continue;
      }

      expect(
        SettingsDataCoverage.backupTableLabels,
        contains(entry.table),
        reason: '${entry.table} needs a user-facing description',
      );
    }
  });

  test('labels only describe tables the backup contract knows', () {
    final known = {
      for (final entry in BackupCoverageContract.tables) entry.table,
    };

    expect(known, containsAll(SettingsDataCoverage.backupTableLabels.keys));
  });

  test('backups and device-only data never share a description', () {
    expect(
      SettingsDataCoverage.inBackups.toSet().intersection(
        SettingsDataCoverage.notInBackups.toSet(),
      ),
      isEmpty,
    );
  });

  test('backups include history, charts and playlists but not audio', () {
    expect(
      SettingsDataCoverage.inBackups,
      containsAll([
        'Listening history and qualified streams',
        'Personal charts and chart moments',
        'Playlists',
      ]),
    );
    expect(SettingsDataCoverage.notInBackups, contains('Audio files'));
  });

  test('cloud sync is described exactly as the sync contract defines it', () {
    expect(
      SettingsDataCoverage.cloudSynced,
      hasLength(SyncDataContract.cloudEntities.length),
    );
    expect(SettingsDataCoverage.cloudSynced, [
      'Artists',
      'Albums',
      'Album editions',
      'Songs',
      'Artwork',
    ]);
    expect(
      SettingsDataCoverage.syncKeepsOnDevice,
      hasLength(SyncDataContract.deviceLocalEntities.length),
    );
  });

  test('nothing is described as both synced and never synced', () {
    expect(
      SettingsDataCoverage.cloudSynced.toSet().intersection(
        SettingsDataCoverage.neverSynced.toSet(),
      ),
      isEmpty,
    );
    expect(SettingsDataCoverage.neverSynced, contains('Playlists'));
    expect(
      SettingsDataCoverage.neverSynced,
      contains('Listening history and qualified streams'),
    );
  });
}
