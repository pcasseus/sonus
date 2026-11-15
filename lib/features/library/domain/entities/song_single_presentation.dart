import 'release_date.dart';

/// A song's own presentation as a Single (App Update 1.3, REF-1.3-04): its
/// single release date and dedicated cover, independent of each other.
///
/// Never a new song: it is keyed by the Song ID it presents, so plays,
/// charts, Moments, playlists and album placements stay where they are.
/// The album's artwork and edition dates are never changed.
class SongSinglePresentation {
  const SongSinglePresentation({
    required this.songId,
    this.releaseDate,
    this.artworkId,
    this.artworkPath,
    this.useArtworkInCharts = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String songId;

  /// The single's own release date, at the precision known.
  final ReleaseDate? releaseDate;

  /// The dedicated cover (a managed artwork asset).
  final String? artworkId;

  /// The cover's file, when read with it.
  final String? artworkPath;

  /// Whether charts and Moments may show the cover for this song.
  final bool useArtworkInCharts;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether nothing is set (the row may as well not exist).
  bool get isEmpty =>
      releaseDate == null && artworkId == null && !useArtworkInCharts;

  /// The usable cover file, if any.
  String? get coverPath {
    final path = artworkPath?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  SongSinglePresentation copyWith({
    ReleaseDate? releaseDate,
    bool clearReleaseDate = false,
    String? artworkId,
    String? artworkPath,
    bool clearArtwork = false,
    bool? useArtworkInCharts,
    DateTime? updatedAt,
  }) => SongSinglePresentation(
    songId: songId,
    releaseDate: clearReleaseDate ? null : releaseDate ?? this.releaseDate,
    artworkId: clearArtwork ? null : artworkId ?? this.artworkId,
    artworkPath: clearArtwork ? null : artworkPath ?? this.artworkPath,
    useArtworkInCharts: useArtworkInCharts ?? this.useArtworkInCharts,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// The stored text of [date] ('YYYY', 'YYYY-MM' or 'YYYY-MM-DD') and its
  /// precision name.
  static (String, String)? encodeDate(ReleaseDate? date) =>
      date == null ? null : (date.iso, date.precision.name);

  /// The date stored as [text] at [precision], or null when either is
  /// missing, the text does not match the precision, or the date does not
  /// exist. Never throws.
  static ReleaseDate? decodeDate(String? text, String? precision) {
    if (text == null || precision == null) return null;
    final date = ReleaseDate.tryParse(text);
    if (date == null || date.precision.name != precision) return null;
    return date.iso == text ? date : null;
  }
}
