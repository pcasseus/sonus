import '../entities/album_edition.dart';

abstract interface class AlbumEditionRepository {
  Future<void> create(AlbumEdition edition);

  Future<void> save(AlbumEdition edition);

  Future<AlbumEdition?> getById(String id);

  Future<List<AlbumEdition>> getAll();

  Future<List<AlbumEdition>> getByAlbumId(String albumId);
}

/// Deletion of an album edition. Separate from [AlbumEditionRepository]
/// because only edition management needs it, and only for editions that
/// hold no tracks.
abstract interface class AlbumEditionDeletionRepository {
  Future<void> delete(String id);
}
