import '../../../artwork/domain/entities/artwork_asset.dart';

abstract interface class CloudArtworkStorage {
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  });
}
