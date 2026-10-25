import '../../domain/entities/song_artist_credit.dart';

/// A performer credited on a project (album), across all of its editions.
class ProjectCollaborator {
  const ProjectCollaborator({
    required this.albumId,
    required this.artistId,
    required this.artistName,
    required this.roles,
    required this.songCount,
  });

  final String albumId;
  final String artistId;
  final String artistName;

  /// Every role the artist holds on the project's songs.
  final Set<SongArtistCreditRole> roles;

  /// Distinct songs of the project the artist is credited on. A song shared
  /// by Standard and Deluxe counts once.
  final int songCount;

  /// The most prominent role, primary first.
  SongArtistCreditRole get leadRole =>
      SongArtistCreditRole.values.firstWhere(roles.contains);
}
