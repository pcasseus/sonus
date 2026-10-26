import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';

class LibraryAlbum {
  const LibraryAlbum({
    required this.albumId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.trackCount,
    required this.dateAdded,
    this.primaryEditionId,
    this.primaryEditionTitle,
    this.primaryEditionType,
    this.releaseDate,
    this.releaseDatePrecision,
    this.genre,
    this.artworkId,
    this.artworkPath,
  });

  final String albumId;
  final String title;

  final String artistId;
  final String artistName;

  final String? primaryEditionId;
  final String? primaryEditionTitle;
  final AlbumEditionType? primaryEditionType;

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

  final int trackCount;
  final DateTime dateAdded;
}
