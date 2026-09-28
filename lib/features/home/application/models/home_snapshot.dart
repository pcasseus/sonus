import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import 'home_popular_track.dart';
import 'home_top_artist.dart';

class HomeSnapshot {
  const HomeSnapshot({
    required this.recentlyAddedTracks,
    required this.recentlyAddedAlbums,
    required this.weeklyPopularTracks,
    required this.weeklyTopArtists,
  });

  final List<LibraryTrack> recentlyAddedTracks;
  final List<LibraryAlbum> recentlyAddedAlbums;
  final List<HomePopularTrack> weeklyPopularTracks;
  final List<HomeTopArtist> weeklyTopArtists;

  bool get isEmpty =>
      recentlyAddedTracks.isEmpty &&
      recentlyAddedAlbums.isEmpty &&
      weeklyPopularTracks.isEmpty &&
      weeklyTopArtists.isEmpty;
}
