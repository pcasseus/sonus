import '../../domain/entities/artwork_asset.dart';
import '../../domain/repositories/artwork_asset_repository.dart';
import '../daos/artwork_asset_dao.dart';

class SqliteArtworkAssetRepository implements ArtworkAssetRepository {
  const SqliteArtworkAssetRepository(this.dao);

  final ArtworkAssetDao dao;

  @override
  Future<void> create(ArtworkAsset artworkAsset) {
    return dao.insert(artworkAsset);
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) {
    return dao.update(artworkAsset);
  }

  @override
  Future<ArtworkAsset?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) {
    return dao.findByNormalizedPath(normalizedPath);
  }

  @override
  Future<List<ArtworkAsset>> getAll() {
    return dao.findAll();
  }
}
