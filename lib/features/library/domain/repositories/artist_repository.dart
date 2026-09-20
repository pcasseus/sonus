import '../entities/artist.dart';

abstract interface class ArtistRepository {
  Future<void> create(Artist artist);

  Future<void> save(Artist artist);

  Future<void> delete(String id);

  Future<Artist?> getById(String id);

  Future<List<Artist>> getAll();
}
