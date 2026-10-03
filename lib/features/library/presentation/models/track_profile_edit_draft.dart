import '../../application/models/library_artist.dart';
import '../../domain/entities/song_artist_credit.dart';

typedef TrackArtistCreationCallback =
    Future<LibraryArtist?> Function(String name);

class TrackProfileCreditDraft {
  const TrackProfileCreditDraft({
    required this.creditedName,
    required this.role,
    this.artistId,
  }) : assert(
         role != SongArtistCreditRole.primary,
         'Additional Track Studio credits cannot use the primary role.',
       );

  final String creditedName;
  final SongArtistCreditRole role;
  final String? artistId;
}

class TrackProfileEditDraft {
  const TrackProfileEditDraft({
    required this.title,
    required this.trackNumber,
    required this.discNumber,
    required this.featuredArtists,
    this.additionalCredits = const [],
    required this.isSingle,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
  });

  final String title;
  final int trackNumber;
  final int discNumber;
  final List<String> featuredArtists;
  final List<TrackProfileCreditDraft> additionalCredits;
  final bool isSingle;

  final String artistId;
  final String albumId;
  final String albumEditionId;
}
