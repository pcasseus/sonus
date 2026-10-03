import '../../application/models/library_artist.dart';

typedef TrackArtistCreationCallback =
    Future<LibraryArtist?> Function(String name);

class TrackProfileEditDraft {
  const TrackProfileEditDraft({
    required this.title,
    required this.trackNumber,
    required this.discNumber,
    required this.featuredArtists,
    required this.isSingle,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
  });

  final String title;
  final int trackNumber;
  final int discNumber;
  final List<String> featuredArtists;
  final bool isSingle;

  final String artistId;
  final String albumId;
  final String albumEditionId;
}
