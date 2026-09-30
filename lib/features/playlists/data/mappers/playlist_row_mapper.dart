import '../../domain/entities/playlist.dart';

abstract final class PlaylistRowMapper {
  static Map<String, Object?> toRow(Playlist playlist) {
    return {
      'id': playlist.id,
      'name': playlist.name,
      'created_at': playlist.createdAt.toUtc().toIso8601String(),
      'updated_at': playlist.updatedAt.toUtc().toIso8601String(),
    };
  }

  static Playlist fromRow(Map<String, Object?> row) {
    return Playlist(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
