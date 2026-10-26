import '../../application/models/library_album_edition.dart';
import '../../domain/entities/album_edition.dart';
import 'album_edition_row_mapper.dart';

abstract final class LibraryAlbumEditionRowMapper {
  static LibraryAlbumEdition fromRow(Map<String, Object?> row) {
    final typeName = row['edition_type'] as String?;

    final type = AlbumEditionType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => AlbumEditionType.other,
    );

    final releaseDate = row['release_date'] as String?;

    return LibraryAlbumEdition(
      editionId: row['album_edition_id'] as String,
      albumId: row['album_id'] as String,
      title: row['album_edition_title'] as String,
      type: type,
      isPrimary: (row['is_primary'] as int? ?? 0) == 1,
      releaseDate: releaseDate == null ? null : DateTime.parse(releaseDate),
      releaseDatePrecision: releaseDatePrecisionOf(
        row['release_date_precision'],
      ),
      genre: row['genre'] as String?,
      artworkId: row['artwork_id'] as String?,
      artworkPath: row['artwork_path'] as String?,
      dateAdded: DateTime.parse(row['created_at'] as String),
    );
  }
}
