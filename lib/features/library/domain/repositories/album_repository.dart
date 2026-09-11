import '../entities/album.dart';

abstract interface class AlbumRepository {
  Future<void> create(Album album);

  Future<void> save(Album album);

  Future<Album?> getById(String id);

  Future<List<Album>> getAll();

  Future<List<Album>> getByArtistId(String artistId);

  Future<List<Album>> getRecentlyAdded(int limit);
}
