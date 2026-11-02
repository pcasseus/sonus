import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';

class LibraryAlbumEdition {
  const LibraryAlbumEdition({
    required this.editionId,
    required this.albumId,
    required this.title,
    required this.type,
    required this.isPrimary,
    required this.dateAdded,
    this.releaseDate,
    this.releaseDatePrecision,
    this.genre,
    this.artworkId,
    this.artworkPath,
  });

  final String editionId;
  final String albumId;
  final String title;
  final AlbumEditionType type;
  final bool isPrimary;

  final DateTime? releaseDate;

  /// How much of [releaseDate] is known; see [ReleaseDatePrecision].
  final ReleaseDatePrecision? releaseDatePrecision;
  final String? genre;

  /// The release date as far as it is known.
  ReleaseDate? get releaseDateValue => releaseDate == null
      ? null
      : ReleaseDate.fromStored(releaseDate!, releaseDatePrecision);

  final String? artworkId;
  final String? artworkPath;

  final DateTime dateAdded;
}
