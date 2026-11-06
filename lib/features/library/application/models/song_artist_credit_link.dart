import '../../domain/entities/song_artist_credit.dart';

/// One structured credit that names a library artist: the song, the artist
/// and the role. Unlinked (name-only) credits have no artist and are not
/// included.
class SongArtistCreditLink {
  const SongArtistCreditLink({
    required this.songId,
    required this.artistId,
    required this.role,
  });

  final String songId;
  final String artistId;
  final SongArtistCreditRole role;

  /// Primary or co-primary: the credits that make a song one of the
  /// artist's own (as `getMainTracksByArtistId` reads them).
  bool get isMain =>
      role == SongArtistCreditRole.primary ||
      role == SongArtistCreditRole.coPrimary;
}
