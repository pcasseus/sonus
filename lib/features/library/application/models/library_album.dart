import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';
import 'release_display_title.dart';

class LibraryAlbum {
  const LibraryAlbum({
    required this.albumId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.trackCount,
    this.songCount,
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

  /// The stored base title; import matching and search keys use it.
  final String title;

  /// The title shown for the release today (SN-50 A-Q3).
  String get displayTitle =>
      releaseDisplayTitle(baseTitle: title, editionTitle: primaryEditionTitle);

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

  /// Tracks on the shown (primary) edition; every song of the release when
  /// it has no primary edition (SN-50 A-Q14A).
  final int trackCount;

  /// Every song of the release, across all editions; null when not read.
  final int? songCount;

  /// Whether the release has any songs, on any edition.
  bool get hasSongs => (songCount ?? trackCount) > 0;
  final DateTime dateAdded;
}
