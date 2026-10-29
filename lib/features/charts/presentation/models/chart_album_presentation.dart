import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_album_edition.dart';
import '../../../library/application/models/release_display_title.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/release_date.dart';

/// How a release looks on the current album chart: the title, cover and
/// edition shown. Its position and streams stay those of the whole
/// release; finalized weekly rows keep the title they were stored with.
class ChartAlbumPresentation {
  const ChartAlbumPresentation({
    required this.title,
    required this.artworkPath,
    required this.editionId,
  });

  /// A Deluxe edition when the release has one, otherwise its primary
  /// edition (SN-50 A-Q21). Among several Deluxes the most recently
  /// released wins; when release dates are missing or can't tell them
  /// apart, the most recently added (A-Q27/A-Q27B). A Deluxe without a
  /// cover keeps the placeholder rather than another edition's cover
  /// (A-Q28).
  factory ChartAlbumPresentation.resolve(
    LibraryAlbum album,
    Iterable<LibraryAlbumEdition> editions,
  ) {
    final deluxe = preferredDeluxe([
      for (final edition in editions)
        if (edition.albumId == album.albumId &&
            edition.type == AlbumEditionType.deluxe)
          edition,
    ]);

    if (deluxe == null) {
      return ChartAlbumPresentation(
        title: album.displayTitle,
        artworkPath: album.artworkPath,
        editionId: album.primaryEditionId,
      );
    }

    final cover = deluxe.artworkPath?.trim();

    return ChartAlbumPresentation(
      title: releaseDisplayTitle(
        baseTitle: album.title,
        editionTitle: deluxe.title,
      ),
      artworkPath: cover == null || cover.isEmpty ? null : cover,
      editionId: deluxe.editionId,
    );
  }

  final String title;
  final String? artworkPath;

  /// The edition Album Profile opens on (A-Q22); null opens its default.
  final String? editionId;

  /// The Deluxe [ChartAlbumPresentation.resolve] shows, or null.
  static LibraryAlbumEdition? preferredDeluxe(
    List<LibraryAlbumEdition> deluxes,
  ) {
    if (deluxes.isEmpty) return null;

    final dated = deluxes.every((edition) => edition.releaseDate != null);
    var candidates = deluxes;

    if (dated) {
      final latest = deluxes.reduce(
        (a, b) =>
            a.releaseDateValue!.compareTo(b.releaseDateValue!) >= 0 ? a : b,
      );
      final date = latest.releaseDateValue!;
      // "2026" and "2026-05-01" could be the same day: an ambiguous tie.
      candidates = [
        for (final edition in deluxes)
          if (_overlaps(edition.releaseDateValue!, date)) edition,
      ];
    }

    return candidates.reduce(_moreRecentlyAdded);
  }

  static bool _overlaps(ReleaseDate a, ReleaseDate b) =>
      a.isRefinedBy(b) || b.isRefinedBy(a);

  static LibraryAlbumEdition _moreRecentlyAdded(
    LibraryAlbumEdition a,
    LibraryAlbumEdition b,
  ) {
    final byAdded = a.dateAdded.compareTo(b.dateAdded);
    if (byAdded != 0) return byAdded > 0 ? a : b;
    return a.editionId.compareTo(b.editionId) >= 0 ? a : b;
  }
}
