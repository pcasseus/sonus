import '../../domain/entities/song_single_presentation.dart';

/// Where a Single's dedicated cover is shown (App Update 1.3, REF-1.3-04),
/// one policy for every surface:
///
/// - Album Profile and edition views: never (the album's artwork stays).
/// - Artist Profile → Singles: the single cover when there is one;
///   otherwise the song's existing artwork ([profileCover]).
/// - Moments: the single cover only when the song is a Single and the
///   listener chose to show it there; otherwise the existing Moments
///   artwork, unchanged ([momentCover]).
/// - Career and weekly chart rows: never. They keep the song's usual
///   library artwork, so a chart's appearance does not change when a song
///   gains a Single cover (App Update 1.3 chart artwork correction).
///
/// A presentation without a usable cover file always falls back. Nothing
/// here changes a stored record, a chart identity or a Moment.
abstract final class SingleCoverPolicy {
  /// The Artist Profile Singles card.
  static String? profileCover({
    required SongSinglePresentation? single,
    required String? existing,
  }) => single?.coverPath ?? _nonEmpty(existing);

  /// A song's picture in Moments. The stored switch is still named
  /// `useArtworkInCharts` (schema v47); it now governs Moments only.
  static String? momentCover({
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
