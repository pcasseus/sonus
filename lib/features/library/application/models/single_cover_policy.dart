import '../../domain/entities/song_single_presentation.dart';

/// Where a Single's dedicated cover is shown (App Update 1.3, REF-1.3-04),
/// one policy for every surface:
///
/// - Album Profile and edition views: never (the album's artwork stays).
/// - Artist Profile → Singles: the single cover when there is one;
///   otherwise the song's existing artwork ([profileCover]).
/// - Charts and Moments: the single cover only when the song is a Single
///   and the listener chose to show it there; otherwise each surface's
///   existing artwork, unchanged ([chartCover]).
///
/// A presentation without a usable cover file always falls back. Nothing
/// here changes a stored record, a chart identity or a Moment.
abstract final class SingleCoverPolicy {
  /// The Artist Profile Singles card.
  static String? profileCover({
    required SongSinglePresentation? single,
    required String? existing,
  }) => single?.coverPath ?? _nonEmpty(existing);

  /// Chart rows and Moments pictures for a song.
  static String? chartCover({
    required bool isSingle,
    required SongSinglePresentation? single,
    required String? existing,
  }) {
    if (isSingle && single != null && single.useArtworkInCharts) {
      final cover = single.coverPath;
      if (cover != null) return cover;
    }
    return _nonEmpty(existing);
  }

  static String? _nonEmpty(String? path) {
    final trimmed = path?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
