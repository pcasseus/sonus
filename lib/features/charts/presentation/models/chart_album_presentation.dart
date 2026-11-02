import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_album_edition.dart';
import '../../../library/application/models/library_release_edition.dart';
import '../../../library/application/models/release_display_title.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/release_date.dart';

/// How a release looks wherever Sonus presents it at album level (the
/// current album chart, release Moments, the edition Album Profile opens):
/// the title, cover and edition shown. Presentation only: its position,
/// streams and stored records stay those of the whole release, and
/// finalized weekly rows keep the title they were stored with.
class ChartAlbumPresentation {
  const ChartAlbumPresentation({
    required this.title,
    required this.artworkPath,
    required this.editionId,
  });

  /// The edition with the most songs represents the release (SN-50): a
  /// Deluxe with more tracks than the standard edition is shown as the
  /// Deluxe, with its title and its cover.
  ///
  /// Songs are counted as the edition's track list shows them (each song
  /// once; [LibraryReleaseEdition.trackCount]). Among editions with the
  /// same, highest count, the earlier rule decides: a Deluxe (the most
  /// recently released, then the most recently added, then the highest
  /// id; A-Q21/A-Q27/A-Q27B), then the primary edition, then the other
  /// editions in the same recency order. Without counts (none loaded, or
  /// the read failed) the primary edition is shown.
  ///
  /// The title and cover always come from the same edition: an edition
  /// without a cover keeps the placeholder rather than another edition's
  /// cover (A-Q28). The primary edition is shown exactly as the album
  /// itself is.
  factory ChartAlbumPresentation.resolve(
    LibraryAlbum album,
    Iterable<LibraryReleaseEdition> editions,
  ) {
    final own = [
      for (final candidate in editions)
        if (candidate.edition.albumId == album.albumId) candidate,
    ];

    final winner = own.isEmpty ? null : _representative(album, own);

    if (winner == null || winner.editionId == album.primaryEditionId) {
      return ChartAlbumPresentation(
        title: album.displayTitle,
        artworkPath: album.artworkPath,
        editionId: album.primaryEditionId,
      );
    }

    final cover = winner.artworkPath?.trim();

    return ChartAlbumPresentation(
      title: releaseDisplayTitle(
        baseTitle: album.title,
        editionTitle: winner.title,
      ),
      artworkPath: cover == null || cover.isEmpty ? null : cover,
      editionId: winner.editionId,
    );
  }

  final String title;
  final String? artworkPath;

  /// The edition Album Profile opens on (A-Q22); null opens its default.
  final String? editionId;

  static LibraryAlbumEdition _representative(
    LibraryAlbum album,
    List<LibraryReleaseEdition> editions,
  ) {
    final most = editions
        .map((candidate) => candidate.trackCount)
        .reduce((a, b) => a >= b ? a : b);
    final tied = [
      for (final candidate in editions)
        if (candidate.trackCount == most) candidate.edition,
    ];

    final deluxe = preferredDeluxe([
      for (final edition in tied)
        if (edition.type == AlbumEditionType.deluxe) edition,
    ]);
    if (deluxe != null) return deluxe;

    for (final edition in tied) {
      if (edition.editionId == album.primaryEditionId) return edition;
    }

    return _mostRecent(tied);
  }

  /// The Deluxe shown among equally long editions, or null: the most
  /// recently released; when release dates are missing or can't tell them
  /// apart, the most recently added (A-Q27/A-Q27B).
  static LibraryAlbumEdition? preferredDeluxe(
    List<LibraryAlbumEdition> deluxes,
  ) => deluxes.isEmpty ? null : _mostRecent(deluxes);

  static LibraryAlbumEdition _mostRecent(List<LibraryAlbumEdition> editions) {
    final dated = editions.every((edition) => edition.releaseDate != null);
    var candidates = editions;

    if (dated) {
      final latest = editions.reduce(
        (a, b) =>
            a.releaseDateValue!.compareTo(b.releaseDateValue!) >= 0 ? a : b,
      );
      final date = latest.releaseDateValue!;
      // "2026" and "2026-05-01" could be the same day: an ambiguous tie.
      candidates = [
        for (final edition in editions)
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
