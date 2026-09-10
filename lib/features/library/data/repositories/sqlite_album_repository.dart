import '../../domain/entities/album.dart';
import '../../domain/repositories/album_repository.dart';
import '../daos/album_dao.dart';

class SqliteAlbumRepository implements AlbumRepository {
  const SqliteAlbumRepository(this.dao);

  final AlbumDao dao;

  @override
  Future<void> create(Album album) {
    return dao.insert(album);
  }

  @override
  Future<void> save(Album album) {
    return dao.update(album);
  }

  @override
  Future<Album?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<Album>> getByArtistId(String artistId) {
    return dao.findByArtistId(artistId);
  }
}
