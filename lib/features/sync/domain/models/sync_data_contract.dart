enum CloudDataEntity { artist, album, albumEdition, song, artworkAsset }

enum DeviceLocalDataEntity { mediaFileBinding, importBatch }

abstract final class SyncDataContract {
  /// Whether edition date precision and disc names are written to the
  /// cloud (App Update 1.2, REF-12b/REF-13c). Off until the proposed cloud
  /// migration 20261113000001 is deployed to production and confirmed.
  /// Reading them back from a server that has them is always on, and a
  /// server without the columns is detected and never sent them either way.
  static const bool editionMetadataExtensionsEnabled = false;

  static const Set<CloudDataEntity> cloudEntities = {
    CloudDataEntity.artist,
    CloudDataEntity.album,
    CloudDataEntity.albumEdition,
    CloudDataEntity.song,
    CloudDataEntity.artworkAsset,
  };

  static const Set<DeviceLocalDataEntity> deviceLocalEntities = {
    DeviceLocalDataEntity.mediaFileBinding,
    DeviceLocalDataEntity.importBatch,
  };

  static bool isCloudEntity(CloudDataEntity entity) {
    return cloudEntities.contains(entity);
  }

  static bool isDeviceLocalEntity(DeviceLocalDataEntity entity) {
    return deviceLocalEntities.contains(entity);
  }
}
