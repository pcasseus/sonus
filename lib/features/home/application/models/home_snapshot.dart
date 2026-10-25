import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import 'home_popular_track.dart';
import 'home_ranking_week.dart';
import 'home_top_artist.dart';

class HomeSnapshot {
  const HomeSnapshot({
    required this.recentlyAddedTracks,
    required this.recentlyAddedAlbums,
    required this.weeklyPopularTracks,
    required this.weeklyTopArtists,
    this.popularTracksWeek = HomeRankingWeek.thisWeek,
    this.topArtistsWeek = HomeRankingWeek.thisWeek,
  });

  final List<LibraryTrack> recentlyAddedTracks;
  final List<LibraryAlbum> recentlyAddedAlbums;
  final List<HomePopularTrack> weeklyPopularTracks;
  final List<HomeTopArtist> weeklyTopArtists;

  /// The week [weeklyPopularTracks] ranks.
  final HomeRankingWeek popularTracksWeek;

  /// The week [weeklyTopArtists] ranks, chosen independently of
  /// [popularTracksWeek].
  final HomeRankingWeek topArtistsWeek;

  bool get isEmpty =>
      recentlyAddedTracks.isEmpty &&
      recentlyAddedAlbums.isEmpty &&
      weeklyPopularTracks.isEmpty &&
      weeklyTopArtists.isEmpty;
}
