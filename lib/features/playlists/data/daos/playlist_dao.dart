import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/playlist_item.dart';
import '../mappers/playlist_item_row_mapper.dart';
import '../mappers/playlist_row_mapper.dart';

class PlaylistDao {
  const PlaylistDao(this.db);

  final DatabaseExecutor db;

  Future<void> insertPlaylist(Playlist playlist) async {
    await db.insert(
      DatabaseTables.playlists,
      PlaylistRowMapper.toRow(playlist),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    final count = await db.update(
      DatabaseTables.playlists,
      PlaylistRowMapper.toRow(playlist),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );

    if (count != 1) {
      throw StateError('Playlist not found: ${playlist.id}');
    }
  }

  Future<void> deletePlaylist(String id) async {
    final count = await db.delete(
      DatabaseTables.playlists,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (count != 1) {
      throw StateError('Playlist not found: $id');
    }
  }

  Future<Playlist?> findPlaylistById(String id) async {
    final rows = await db.query(
      DatabaseTables.playlists,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return PlaylistRowMapper.fromRow(rows.single);
  }

  Future<List<Playlist>> findPlaylists() async {
    final rows = await db.query(
      DatabaseTables.playlists,
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(PlaylistRowMapper.fromRow).toList(growable: false);
  }

  Future<void> insertItem(PlaylistItem item) async {
    await db.insert(
      DatabaseTables.playlistItems,
      PlaylistItemRowMapper.toRow(item),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateItem(PlaylistItem item) async {
    final count = await db.update(
      DatabaseTables.playlistItems,
      PlaylistItemRowMapper.toRow(item),
      where: 'id = ?',
      whereArgs: [item.id],
    );

    if (count != 1) {
      throw StateError('Playlist item not found: ${item.id}');
    }
  }

  Future<void> deleteItem(String id) async {
    final count = await db.delete(
      DatabaseTables.playlistItems,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (count != 1) {
      throw StateError('Playlist item not found: $id');
    }
  }

  Future<PlaylistItem?> findItemById(String id) async {
    final rows = await db.query(
      DatabaseTables.playlistItems,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return PlaylistItemRowMapper.fromRow(rows.single);
  }

  Future<List<PlaylistItem>> findItemsByPlaylistId(String playlistId) async {
    final rows = await db.query(
      DatabaseTables.playlistItems,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC, created_at ASC, id ASC',
    );

    return rows.map(PlaylistItemRowMapper.fromRow).toList(growable: false);
  }
}
