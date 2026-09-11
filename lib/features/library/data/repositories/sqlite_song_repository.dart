import '../../domain/entities/song.dart';
import '../../domain/repositories/song_repository.dart';
import '../daos/song_dao.dart';

class SqliteSongRepository implements SongRepository {
  const SqliteSongRepository(this.dao);

  final SongDao dao;

  @override
  Future<void> create(Song song) {
    return dao.insert(song);
  }

  @override
  Future<void> save(Song song) {
    return dao.update(song);
  }

  @override
  Future<Song?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<Song>> getAll() {
    return dao.findAll();
  }

  @override
  Future<List<Song>> getByArtistId(String artistId) {
    return dao.findByArtistId(artistId);
  }

  @override
  Future<List<Song>> getByAlbumId(String albumId) {
    return dao.findByAlbumId(albumId);
  }

  @override
  Future<List<Song>> getByEditionId(String editionId) {
    return dao.findByEditionId(editionId);
  }

  @override
  Future<List<Song>> getRecentlyAdded(int limit) {
    return dao.findRecentlyAdded(limit);
  }
}
