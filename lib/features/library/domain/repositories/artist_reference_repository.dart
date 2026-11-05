/// Something in Sonus that still refers to an artist, so removing the
/// artist would break it. Removal is refused while any exists.
enum ArtistReference {
  /// Albums the artist owns.
  albums,

  /// Songs whose primary artist this is.
  songs,

  /// Song credits (co-primary, featured, guest).
  credits,

  /// Where the artist is placed in the Library (grouped or standalone).
  projectAssignment,

  /// Playback sessions or qualified plays: listening statistics.
  listeningHistory,

  /// Chart entries, live or finalized.
  charts,

  /// Moments that name the artist, as subject or as related artist.
  moments,

  /// Artist writes or creations still being confirmed with the cloud.
  pendingCloudWrite,
}

/// Read-only lookups of what still refers to an artist. Used inside the
/// removal transaction, so the answer cannot go stale before the delete.
abstract interface class ArtistReferenceRepository {
  /// Every kind of reference [artistId] still has; empty when the artist
  /// is safe to remove.
  Future<Set<ArtistReference>> findReferences(String artistId);
}
