import '../../domain/entities/artist.dart';
import '../../domain/repositories/artist_repository.dart';
import '../daos/artist_dao.dart';

class SqliteArtistRepository implements ArtistRepository {
  const SqliteArtistRepository(this.dao);

  final ArtistDao dao;

  @override
  Future<void> create(Artist artist) {
    return dao.insert(artist);
  }

  @override
  Future<void> save(Artist artist) {
    return dao.update(artist);
  }

  @override
  Future<void> delete(String id) {
    return dao.delete(id);
  }

  @override
  Future<Artist?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<Artist>> getAll() {
    return dao.findAll();
  }
}
