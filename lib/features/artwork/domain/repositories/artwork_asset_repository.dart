import '../entities/artwork_asset.dart';

abstract interface class ArtworkAssetRepository {
  Future<void> create(ArtworkAsset artworkAsset);

  Future<void> save(ArtworkAsset artworkAsset);

  Future<ArtworkAsset?> getById(String id);

  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath);

  Future<List<ArtworkAsset>> getAll();
}
