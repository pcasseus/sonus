import '../../domain/entities/album.dart';

abstract final class AlbumRowMapper {
  static Map<String, Object?> toRow(Album album) {
    return {
      'id': album.id,
      'artist_id': album.artistId,
      'title': album.title,
      'canonical_title': album.canonicalTitle,
      'created_at': album.createdAt.toUtc().toIso8601String(),
      'updated_at': album.updatedAt.toUtc().toIso8601String(),
    };
  }

  static Album fromRow(Map<String, Object?> row) {
    return Album(
      id: row['id'] as String,
      artistId: row['artist_id'] as String,
      title: row['title'] as String,
      canonicalTitle: row['canonical_title'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
