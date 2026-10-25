import '../../../../core/database/database_tables.dart';
import '../../../recovery/application/models/backup_table_coverage.dart';
import '../../../sync/domain/models/sync_data_contract.dart';

/// Plain-language descriptions of where each kind of Sonus data lives,
/// derived from the real sync and backup contracts so Settings never claims
/// more (or less) than the app actually does.
abstract final class SettingsDataCoverage {
  /// What cloud sync uploads to the signed-in account.
  static List<String> get cloudSynced => [
    for (final entity in SyncDataContract.cloudEntities) _cloudLabel(entity),
  ];

  /// Data cloud sync deliberately keeps on this device.
  static List<String> get syncKeepsOnDevice => [
    for (final entity in SyncDataContract.deviceLocalEntities)
      _deviceLocalLabel(entity),
  ];

  /// Library data that exists in Sonus but is not part of the sync
  /// contract. Backups still include everything here except preferences.
  static const List<String> neverSynced = [
    'Playlists',
    'Listening history and qualified streams',
    'Personal charts and chart moments',
    'Lyrics',
    'Metadata authority and review decisions',
    'Appearance and playback preferences',
  ];

  /// What a Sonus backup preserves, grouped for people rather than tables.
  static List<String> get inBackups =>
      _labelsFor(BackupTablePolicy.portableData);

  /// What a backup leaves out because it only makes sense on this device.
  static List<String> get notInBackups => [
    ..._labelsFor(BackupTablePolicy.deviceLocal),
    'Audio files',
    'Appearance and playback preferences',
  ];

  /// The category each backed-up or device-local table is described as.
  /// Internal sync and ownership tables are never described to users.
  static const Map<String, String> backupTableLabels = {
    DatabaseTables.artists: 'Artists, albums, editions and songs',
    DatabaseTables.albums: 'Artists, albums, editions and songs',
    DatabaseTables.albumEditions: 'Artists, albums, editions and songs',
    DatabaseTables.albumEditionTracks: 'Artists, albums, editions and songs',
    DatabaseTables.songs: 'Artists, albums, editions and songs',
    DatabaseTables.songArtistCredits: 'Artists, albums, editions and songs',
    DatabaseTables.artworkAssets: 'Artwork you added or chose',
    DatabaseTables.metadataFieldStates:
        'Metadata authority and review decisions',
    DatabaseTables.trackLyrics: 'Lyrics',
    DatabaseTables.playbackSessions: 'Listening history and qualified streams',
    DatabaseTables.playbackListeningSegments:
        'Listening history and qualified streams',
    DatabaseTables.qualifiedPlays: 'Listening history and qualified streams',
    DatabaseTables.chartSnapshots: 'Personal charts and chart moments',
    DatabaseTables.chartEntries: 'Personal charts and chart moments',
    DatabaseTables.chartMomentEvents: 'Personal charts and chart moments',
    DatabaseTables.playlists: 'Playlists',
    DatabaseTables.playlistItems: 'Playlists',
    DatabaseTables.mediaFileBindings:
        'Locations of your audio files on this device',
    DatabaseTables.importBatches: 'Import history and music folders',
    DatabaseTables.importSources: 'Import history and music folders',
    DatabaseTables.songImportReviews: 'Pending import reviews',
    DatabaseTables.albumReleaseClassifications:
        'Soundtrack and collaborator organization',
    DatabaseTables.artistProjectAssignments:
        'Soundtrack and collaborator organization',
    DatabaseTables.artworkCrops: 'How covers and artist photos are cropped',
  };

  static List<String> _labelsFor(BackupTablePolicy policy) {
    final labels = <String>[];

    for (final entry in BackupCoverageContract.tables) {
      if (entry.policy != policy) {
        continue;
      }

      final label = backupTableLabels[entry.table];
      if (label != null && !labels.contains(label)) {
        labels.add(label);
      }
    }

    return labels;
  }

  static String _cloudLabel(CloudDataEntity entity) => switch (entity) {
    CloudDataEntity.artist => 'Artists',
    CloudDataEntity.album => 'Albums',
    CloudDataEntity.albumEdition => 'Album editions',
    CloudDataEntity.song => 'Songs',
    CloudDataEntity.artworkAsset => 'Artwork',
  };

  static String _deviceLocalLabel(DeviceLocalDataEntity entity) =>
      switch (entity) {
        DeviceLocalDataEntity.mediaFileBinding =>
          'Locations of your audio files',
        DeviceLocalDataEntity.importBatch => 'Import history',
      };
}
