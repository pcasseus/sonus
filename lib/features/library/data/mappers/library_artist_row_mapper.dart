import '../../application/models/library_artist.dart';

abstract final class LibraryArtistRowMapper {
  static LibraryArtist fromRow(Map<String, Object?> row) {
    return LibraryArtist(
      artistId: row['artist_id'] as String,
      name: row['artist_name'] as String,
      albumCount: row['album_count'] as int? ?? 0,
      songCount: row['song_count'] as int? ?? 0,
      dateAdded: DateTime.parse(row['created_at'] as String),
    );
  }
}
