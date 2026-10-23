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

  /// Removes an object that no accepted cloud row references.
  Future<void> deleteObject({
    required String userId,
    required String objectKey,
  });
}
