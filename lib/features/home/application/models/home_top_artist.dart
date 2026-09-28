import '../../../library/application/models/library_artist.dart';

class HomeTopArtist {
  const HomeTopArtist({
    required this.artist,
    required this.rank,
    required this.qualifiedStreamCount,
  });

  final LibraryArtist artist;
  final int rank;
  final int qualifiedStreamCount;
}
