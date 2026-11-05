import '../../../library/application/models/library_artist.dart';

class HomeTopArtist {
  const HomeTopArtist({
    required this.artist,
    required this.rank,
    required this.qualifiedStreamCount,
    required this.weeklyListeningDuration,
    this.isAvailable = true,
    this.isHistorical = false,
  });

  final LibraryArtist artist;
  final int rank;
  final int qualifiedStreamCount;
  final Duration weeklyListeningDuration;
  final bool isAvailable;

  /// The ranked artist is no longer in the library (S2). [artist] then
  /// carries only the id and the name stored when it was played; the
  /// entry keeps its rank and totals but opens no profile.
  final bool isHistorical;
}
