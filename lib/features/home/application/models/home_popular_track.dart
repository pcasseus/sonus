import '../../../library/application/models/library_track.dart';

class HomePopularTrack {
  const HomePopularTrack({
    required this.track,
    required this.rank,
    required this.qualifiedStreamCount,
  });

  final LibraryTrack track;
  final int rank;
  final int qualifiedStreamCount;
}
