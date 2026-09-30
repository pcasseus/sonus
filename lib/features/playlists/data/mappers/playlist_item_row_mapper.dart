import '../../domain/entities/playlist_item.dart';

abstract final class PlaylistItemRowMapper {
  static Map<String, Object?> toRow(PlaylistItem item) {
    return {
      'id': item.id,
      'playlist_id': item.playlistId,
      'song_id': item.songId,
      'position': item.position,
      'created_at': item.createdAt.toUtc().toIso8601String(),
      'updated_at': item.updatedAt.toUtc().toIso8601String(),
    };
  }

  static PlaylistItem fromRow(Map<String, Object?> row) {
    return PlaylistItem(
      id: row['id'] as String,
      playlistId: row['playlist_id'] as String,
      songId: row['song_id'] as String,
      position: row['position'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
