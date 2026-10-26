import '../../application/models/library_album.dart';
import '../../domain/entities/album_edition.dart';
import 'album_edition_row_mapper.dart';

abstract final class LibraryAlbumRowMapper {
  static LibraryAlbum fromRow(Map<String, Object?> row) {
    final editionTypeName = row['primary_edition_type'] as String?;

    final editionType = editionTypeName == null
        ? null
        : AlbumEditionType.values.firstWhere(
            (value) => value.name == editionTypeName,
            orElse: () => AlbumEditionType.other,
          );

    return LibraryAlbum(
      albumId: row['album_id'] as String,
      title: row['album_title'] as String,
      artistId: row['artist_id'] as String,
      artistName: row['artist_name'] as String,
      primaryEditionId: row['primary_edition_id'] as String?,
      primaryEditionTitle: row['primary_edition_title'] as String?,
      primaryEditionType: editionType,
      releaseDate: row['release_date'] == null
          ? null
          : DateTime.parse(row['release_date'] as String),
      releaseDatePrecision: releaseDatePrecisionOf(
        row['release_date_precision'],
      ),
      genre: row['genre'] as String?,
      artworkId: row['artwork_id'] as String?,
      artworkPath: row['artwork_path'] as String?,
      trackCount: row['track_count'] as int? ?? 0,
      dateAdded: DateTime.parse(row['created_at'] as String),
    );
  }
}
