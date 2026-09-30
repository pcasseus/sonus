import '../entities/playlist.dart';
import '../entities/playlist_item.dart';

abstract interface class PlaylistRepository {
  Future<void> create(Playlist playlist);

  Future<void> save(Playlist playlist);

  Future<void> delete(String id);

  Future<Playlist?> getById(String id);

  Future<List<Playlist>> getAll();

  Future<void> addItem(PlaylistItem item);

  Future<void> saveItem(PlaylistItem item);

  Future<void> removeItem(String id);

  Future<PlaylistItem?> getItemById(String id);

  Future<List<PlaylistItem>> getItems(String playlistId);
}
