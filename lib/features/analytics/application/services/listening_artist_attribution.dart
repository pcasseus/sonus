/// Which artist a play counts for in artist-level statistics (top artists,
/// artist listening time, Year in Sonus, artist chart Moments).
///
/// Plays store the song's performer when they qualified. A performer that
/// has no release of its own is a contributor to someone else's project, so
/// its plays count for that project's owner instead. Every play still
/// counts for exactly one artist, and stored plays never change.
abstract interface class ListeningArtistAttribution {
  Future<ArtistAttributor> load();
}

/// A loaded attribution: [artistFor] maps a play's stored artist and album
/// to the artist it counts for.
class ArtistAttributor {
  const ArtistAttributor(this._artistFor);

  /// Every play counts for its stored artist.
  static const ArtistAttributor identity = ArtistAttributor(_stored);

  final String Function(String artistId, String albumId) _artistFor;

  String artistFor({required String artistId, required String albumId}) =>
      _artistFor(artistId, albumId);

  static String _stored(String artistId, String albumId) => artistId;

  /// Loads [attribution], or [identity] when there is none.
  static Future<ArtistAttributor> of(ListeningArtistAttribution? attribution) =>
      attribution?.load() ?? Future.value(identity);
}
