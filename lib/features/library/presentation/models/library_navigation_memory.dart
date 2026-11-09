import 'artist_library_statistics.dart';

typedef LibraryNavigationClock = DateTime Function();

/// Where the Artist Roster left off, kept in memory for a short while (App
/// Update 1.1): the featured artist and the sort it was featured in. The
/// Roster's page follows from them, since the featured artist is always on
/// the visible page.
///
/// - Entering the Library destination again (a tab or a swipe) starts the
///   Roster on Page 1 with the first artist featured ([startOver], App
///   Update 1.2, BUG-01). An Artist Profile opened from the Roster never
///   leaves the Library, so going back to the Roster keeps its place.
/// - Sending the app to the background starts a [window] of 15 minutes.
///   Coming back within it restores the artist and sort, if the artist is
///   still listed; after it, the Roster starts again on Page 1 with the
///   first artist featured.
/// - Nothing is written to the database, preferences or the cloud, so a
///   fresh launch always starts on Page 1, Artist 1.
/// - The window is checked when the Roster is entered again, never while
///   it is being browsed.
class LibraryNavigationMemory {
  LibraryNavigationMemory({LibraryNavigationClock? clock})
    : _clock = clock ?? DateTime.now;

  /// The one memory of this app process.
  static final LibraryNavigationMemory shared = LibraryNavigationMemory();

  /// How long a left Roster is remembered.
  static const Duration window = Duration(minutes: 15);

  final LibraryNavigationClock _clock;

  String? _artistId;
  ArtistStatisticsSort? _sort;
  DateTime? _leftAt;

  /// While browsing: the featured artist now.
  void rememberArtist(String? artistId) => _artistId = artistId;

  /// While browsing: the sort now.
  void rememberSort(ArtistStatisticsSort sort) => _sort = sort;

  /// The Roster is left: the window starts now.
  void leave() => _leftAt ??= _clock();

  /// The Library destination is entered: whatever was kept is forgotten,
  /// so the Roster starts on Page 1 with the first artist.
  void startOver() {
    _leftAt = null;
    _forget();
  }

  /// The Roster is entered (again). Returns what to restore, or null to
  /// start on Page 1 with the first artist (nothing remembered, or the
  /// window has passed, which also forgets it).
  ({String artistId, ArtistStatisticsSort? sort})? enter() {
    final artistId = _artistId;
    final leftAt = _leftAt;
    _leftAt = null;
    if (artistId == null || leftAt == null) return _forget();
    if (_clock().difference(leftAt) > window) return _forget();
    return (artistId: artistId, sort: _sort);
  }

  Null _forget() {
    _artistId = null;
    _sort = null;
    return null;
  }
}
