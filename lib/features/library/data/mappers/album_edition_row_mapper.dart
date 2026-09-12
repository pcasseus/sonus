import '../../domain/entities/album_edition.dart';

abstract final class AlbumEditionRowMapper {
  static Map<String, Object?> toRow(AlbumEdition edition) {
    return {
      'id': edition.id,
      'album_id': edition.albumId,
      'title': edition.title,
      'type': edition.type.name,
      'is_primary': edition.isPrimary ? 1 : 0,
      'release_date': edition.releaseDate?.toUtc().toIso8601String(),
      'genre': edition.genre,
      'artwork_id': edition.artworkId,
      'created_at': edition.createdAt.toUtc().toIso8601String(),
      'updated_at': edition.updatedAt.toUtc().toIso8601String(),
    };
  }

  static AlbumEdition fromRow(Map<String, Object?> row) {
    return AlbumEdition(
      id: row['id'] as String,
      albumId: row['album_id'] as String,
      title: row['title'] as String,
      type: AlbumEditionType.values.firstWhere(
        (value) => value.name == row['type'],
        orElse: () => AlbumEditionType.other,
      ),
      isPrimary: (row['is_primary'] as int? ?? 0) == 1,
      releaseDate: row['release_date'] == null
          ? null
          : DateTime.parse(row['release_date'] as String),
      genre: row['genre'] as String?,
      artworkId: row['artwork_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
