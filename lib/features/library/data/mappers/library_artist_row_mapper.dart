import '../../application/models/library_artist.dart';

abstract final class LibraryArtistRowMapper {
  static LibraryArtist fromRow(Map<String, Object?> row) {
    return LibraryArtist(
      artistId: row['artist_id'] as String,
      name: row['artist_name'] as String,
      albumCount: row['album_count'] as int? ?? 0,
      songCount: row['song_count'] as int? ?? 0,
      isBlacklisted: (row['is_blacklisted'] as int? ?? 0) == 1,
      dateAdded: DateTime.parse(row['created_at'] as String),
      headerArtworkId: row['header_artwork_id'] as String?,
      headerArtworkPath: row['header_artwork_path'] as String?,
      topArtistsArtworkId: row['top_artists_artwork_id'] as String?,
      topArtistsArtworkPath: row['top_artists_artwork_path'] as String?,
    );
  }
}
