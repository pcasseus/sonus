import '../entities/album_edition.dart';

abstract interface class AlbumEditionRepository {
  Future<void> create(AlbumEdition edition);

  Future<void> save(AlbumEdition edition);

  Future<AlbumEdition?> getById(String id);

  Future<List<AlbumEdition>> getAll();

  Future<List<AlbumEdition>> getByAlbumId(String albumId);
}
