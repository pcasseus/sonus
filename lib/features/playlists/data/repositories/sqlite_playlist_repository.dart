import '../../domain/entities/playlist.dart';
import '../../domain/entities/playlist_item.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../daos/playlist_dao.dart';

class SqlitePlaylistRepository implements PlaylistRepository {
  const SqlitePlaylistRepository(this.dao);

  final PlaylistDao dao;

  @override
  Future<void> create(Playlist playlist) {
    return dao.insertPlaylist(playlist);
  }

  @override
  Future<void> save(Playlist playlist) {
    return dao.updatePlaylist(playlist);
  }

  @override
  Future<void> delete(String id) {
    return dao.deletePlaylist(id);
  }

  @override
  Future<Playlist?> getById(String id) {
    return dao.findPlaylistById(id);
  }

  @override
  Future<List<Playlist>> getAll() {
    return dao.findPlaylists();
  }

  @override
  Future<void> addItem(PlaylistItem item) {
    return dao.insertItem(item);
  }

  @override
  Future<void> saveItem(PlaylistItem item) {
    return dao.updateItem(item);
  }

  @override
  Future<void> removeItem(String id) {
    return dao.deleteItem(id);
  }

  @override
  Future<PlaylistItem?> getItemById(String id) {
    return dao.findItemById(id);
  }

  @override
  Future<List<PlaylistItem>> getItems(String playlistId) {
    return dao.findItemsByPlaylistId(playlistId);
  }
}
