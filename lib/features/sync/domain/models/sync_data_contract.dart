enum CloudDataEntity { artist, album, albumEdition, song, artworkAsset }

enum DeviceLocalDataEntity { mediaFileBinding, importBatch }

abstract final class SyncDataContract {
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
