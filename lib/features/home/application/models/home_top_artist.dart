import '../../../library/application/models/library_artist.dart';

class HomeTopArtist {
  const HomeTopArtist({
    required this.artist,
    required this.rank,
    required this.qualifiedStreamCount,
    required this.weeklyListeningDuration,
  });

  final LibraryArtist artist;
  final int rank;
  final int qualifiedStreamCount;
  final Duration weeklyListeningDuration;
}
