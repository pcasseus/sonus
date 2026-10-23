import '../../../artwork/domain/entities/artwork_asset.dart';

abstract interface class CloudArtworkStorage {
  /// Legacy deterministic key, replaced on every upload. Only for callers
  /// without revision baselines.
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  });

  /// Uploads to a key unique to [version] without ever replacing an
  /// existing object, so no accepted cloud row can have its artwork bytes
  /// changed underneath it.
  ///
  /// An object already stored at that key is reused only because callers
  /// derive [version] from a single attempt identity.
  Future<String> uploadImmutable({
    required String userId,
    required ArtworkAsset artworkAsset,
    required String version,
  });

  /// Streams the artwork object at [objectKey] into a new file created
  /// exclusively in [directoryPath] and returns that file's path.
  ///
  /// The key must be an approved artwork key for exactly [userId] and
  /// [artworkId]; otherwise nothing is requested. The download stops as
  /// soon as more than [maxBytes] arrive. On any failure the partial file
  /// is removed. No existing file is ever overwritten.
  Future<String> downloadToTemporaryFile({
    required String userId,
    required String artworkId,
    required String objectKey,
    required String directoryPath,
    required int maxBytes,
  });

  /// Removes an object that no accepted cloud row references.
  Future<void> deleteObject({
    required String userId,
    required String objectKey,
  });
}
