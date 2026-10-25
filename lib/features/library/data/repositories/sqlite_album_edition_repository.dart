import '../../domain/entities/album_edition.dart';
import '../../domain/repositories/album_edition_repository.dart';
import '../daos/album_edition_dao.dart';

class SqliteAlbumEditionRepository
    implements AlbumEditionRepository, AlbumEditionDeletionRepository {
  const SqliteAlbumEditionRepository(this.dao);

  final AlbumEditionDao dao;

  @override
  Future<void> create(AlbumEdition edition) {
    return dao.insert(edition);
  }

  @override
  Future<void> save(AlbumEdition edition) {
    return dao.update(edition);
  }

  @override
  Future<AlbumEdition?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<AlbumEdition>> getAll() {
    return dao.findAll();
  }

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) {
    return dao.findByAlbumId(albumId);
  }

  @override
  Future<void> delete(String id) {
    return dao.delete(id);
  }
}
