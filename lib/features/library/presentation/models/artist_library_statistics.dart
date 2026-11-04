import '../../application/models/library_artist.dart';
import 'artist_profile_sections.dart';

/// One artist's statistics for the Film Reel and Artist Roster (UI redesign
/// D1), with the same definitions as the Artist Profile:
/// - [albumCount] and [songCount] are the library's own counts (D5);
/// - [rank] and [qualifiedStreams] come from the all-time artist ranking,
///   attributed as on the profile; an artist without qualified streams is
///   unranked (D4);
/// - [listened] is all-time listening time, attributed the same way;
/// - [topTrack] is the profile's first Top Track.
///
/// Read-only: nothing here is stored or recalculated into history.
class ArtistLibraryStatistics {
  const ArtistLibraryStatistics({
    required this.artist,
    this.rank,
    this.qualifiedStreams = 0,
    this.listened,
    this.topTrack,
  });

  final LibraryArtist artist;

  /// Place in the all-time artist ranking, from 1; null when unranked.
  final int? rank;

  /// All-time qualified streams counted for this artist; 0 when none.
  final int qualifiedStreams;

  /// All-time listening time counted for this artist: zero when none, null
  /// when listening history could not be read.
  final Duration? listened;

  /// The artist's most streamed song, or null when none has a stream.
  final ArtistTopTrack? topTrack;

  String get artistId => artist.artistId;
  String get name => artist.name;
  int get albumCount => artist.albumCount;
  int get songCount => artist.songCount;
  DateTime get dateAdded => artist.dateAdded;

  /// Shown as "Unranked" when false (D4).
  bool get isRanked => rank != null;
}

/// How artists can be ordered in the Roster.
enum ArtistStatisticsSort {
  /// A-Z, as the library lists artists.
  name,

  /// Ranked artists by rank, then unranked artists by name (D4).
  qualifiedStreams,

  /// Most listening time first; artists with none, or unknown, by name
  /// after the rest.
  listeningTime,

  /// Newest artists first.
  recentlyAdded,
}

/// The statistics of every artist, loaded together.
class ArtistLibraryStatisticsSnapshot {
  ArtistLibraryStatisticsSnapshot(Iterable<ArtistLibraryStatistics> artists)
    : _byId = {for (final stats in artists) stats.artistId: stats};

  final Map<String, ArtistLibraryStatistics> _byId;

  static final ArtistLibraryStatisticsSnapshot empty =
      ArtistLibraryStatisticsSnapshot(const []);

  /// The statistics for [artistId], if the artist is in the library.
  ArtistLibraryStatistics? operator [](String artistId) => _byId[artistId];

  Iterable<ArtistLibraryStatistics> get all => _byId.values;

  int get length => _byId.length;

  /// [artistIds] (every artist when null) ordered by [sort]. Ties fall back
  /// to name, then id, so the order is always the same.
  List<ArtistLibraryStatistics> sorted(
    ArtistStatisticsSort sort, {
    Iterable<String>? artistIds,
  }) {
    final selected = artistIds == null
        ? _byId.values.toList()
        : [for (final id in artistIds) ?_byId[id]];
    selected.sort(comparator(sort));
    return List.unmodifiable(selected);
  }

  static int Function(ArtistLibraryStatistics, ArtistLibraryStatistics)
  comparator(ArtistStatisticsSort sort) => switch (sort) {
    ArtistStatisticsSort.name => _byName,
    ArtistStatisticsSort.qualifiedStreams => _byRank,
    ArtistStatisticsSort.listeningTime => _byListening,
    ArtistStatisticsSort.recentlyAdded => _byRecentlyAdded,
  };

  static int _byName(ArtistLibraryStatistics a, ArtistLibraryStatistics b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.artistId.compareTo(b.artistId);
  }

  static int _byRank(ArtistLibraryStatistics a, ArtistLibraryStatistics b) {
    final ra = a.rank;
    final rb = b.rank;
    if (ra != null && rb != null) {
      final byRank = ra.compareTo(rb);
      if (byRank != 0) return byRank;
    } else if (ra != null) {
      return -1;
    } else if (rb != null) {
      return 1;
    }
    return _byName(a, b);
  }

  static int _byListening(
    ArtistLibraryStatistics a,
    ArtistLibraryStatistics b,
  ) {
    final la = a.listened ?? Duration.zero;
    final lb = b.listened ?? Duration.zero;
    final byTime = lb.compareTo(la);
    return byTime != 0 ? byTime : _byName(a, b);
  }

  static int _byRecentlyAdded(
    ArtistLibraryStatistics a,
    ArtistLibraryStatistics b,
  ) {
    final byDate = b.dateAdded.compareTo(a.dateAdded);
    return byDate != 0 ? byDate : _byName(a, b);
  }
}
