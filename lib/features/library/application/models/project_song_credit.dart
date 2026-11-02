import '../../domain/entities/song_artist_credit.dart';

/// One structured credit on a song of a project (album), on any edition.
class ProjectSongCredit {
  const ProjectSongCredit({
    required this.albumId,
    required this.songId,
    required this.creditedName,
    required this.role,
    this.artistId,
  });

  final String albumId;
  final String songId;

  /// The linked library artist; null while the credit is only a name.
  final String? artistId;
  final String creditedName;
  final SongArtistCreditRole role;
}
