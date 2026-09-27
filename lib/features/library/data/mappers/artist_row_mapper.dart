import '../../domain/entities/artist.dart';

abstract final class ArtistRowMapper {
  static Map<String, Object?> toRow(Artist artist) {
    return {
      'id': artist.id,
      'name': artist.name,
      'canonical_name': artist.canonicalName,
      'created_at': artist.createdAt.toUtc().toIso8601String(),
      'updated_at': artist.updatedAt.toUtc().toIso8601String(),
      'header_artwork_id': artist.headerArtworkId,
      'top_artists_artwork_id': artist.topArtistsArtworkId,
    };
  }

  static Artist fromRow(Map<String, Object?> row) {
    return Artist(
      id: row['id'] as String,
      name: row['name'] as String,
      canonicalName: row['canonical_name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      headerArtworkId: row['header_artwork_id'] as String?,
      topArtistsArtworkId: row['top_artists_artwork_id'] as String?,
    );
  }
}
