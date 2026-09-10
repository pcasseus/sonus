import '../entities/song.dart';

abstract interface class SongRepository {
  Future<void> create(Song song);

  Future<void> save(Song song);

  Future<Song?> getById(String id);

  Future<List<Song>> getByArtistId(String artistId);

  Future<List<Song>> getByAlbumId(String albumId);

  Future<List<Song>> getByEditionId(String editionId);
}
