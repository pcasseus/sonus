import '../../application/models/library_artist.dart';
import 'alphabet_index.dart';
import 'artist_library_statistics.dart';

/// What the Artist Roster lists (UI redesign L2): the Library's artists,
/// narrowed by a search and ordered by a sort, cut into pages of the
/// portrait grid. Pure: statistics come from the D1 snapshot and are only
/// read, never recalculated.
class ArtistRosterView {
  factory ArtistRosterView({
    required List<LibraryArtist> artists,
    required ArtistLibraryStatisticsSnapshot statistics,
    required ArtistStatisticsSort sort,
    String query = '',
  }) {
    final needle = _normalise(query);
    final rows = [
      for (final artist in artists)
        if (needle.isEmpty || _normalise(artist.name).contains(needle))
          statistics[artist.artistId] ??
              // Not loaded yet: listed by name, unranked, until it is.
              ArtistLibraryStatistics(artist: artist),
    ]..sort(ArtistLibraryStatisticsSnapshot.comparator(sort));
    return ArtistRosterView._(
      List.unmodifiable([for (final row in rows) row.artist]),
      sort,
    );
  }

  ArtistRosterView._(this.artists, this.sort);

  /// The artists to show, in order.
  final List<LibraryArtist> artists;
  final ArtistStatisticsSort sort;

  bool get isEmpty => artists.isEmpty;

  /// How many pages of [perPage] portraits the artists fill (at least 1).
  int pageCount(int perPage) =>
      artists.isEmpty ? 1 : (artists.length + perPage - 1) ~/ perPage;

  /// The page showing [artistId], or null when it is not listed.
  int? pageOf(String artistId, int perPage) {
    final index = artists.indexWhere((a) => a.artistId == artistId);
    return index < 0 ? null : index ~/ perPage;
  }

  /// The artists on [page].
  List<LibraryArtist> page(int page, int perPage) {
    final start = page * perPage;
    if (start >= artists.length) return const [];
    final end = start + perPage;
    return artists.sublist(start, end > artists.length ? artists.length : end);
  }

  /// Where each letter starts, for A-Z. Meaningful when sorted by name.
  late final AlphabetIndex alphabet = AlphabetIndex.build([
    for (final artist in artists) artist.name,
  ]);

  /// The first artist filed under [letter] (or the nearest letter that has
  /// one), for an A-Z jump; null when the list is empty.
  LibraryArtist? firstFor(String letter) {
    final index = alphabet.indexFor(letter);
    return index == null ? null : artists[index];
  }

  static String _normalise(String value) => value.trim().toLowerCase();
}
