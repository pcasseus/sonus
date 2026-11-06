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

/// Where an artist stands, derived from what refers to it (product decision
/// D8). Nothing is stored: an import or edit that uses the artist again
/// makes it [active] at once.
enum ArtistLibraryState {
  /// A song, album, credit or Library grouping uses the artist.
  active,

  /// Nothing in the library uses the artist any more, but listening
  /// history, charts or Moments still name it. Kept, with its id and name.
  retired,

  /// Nothing uses the artist except changes still being confirmed with the
  /// cloud. Not offered for removal until they are.
  waitingForSync,

  /// Nothing refers to the artist at all; it may be removed.
  removable,
}

/// Library content: while any is present the artist is [ArtistLibraryState.active].
const Set<ArtistReference> artistLibraryReferences = {
  ArtistReference.albums,
  ArtistReference.songs,
  ArtistReference.credits,
  ArtistReference.projectAssignment,
};

/// History that keeps an artist that no library content uses any more.
const Set<ArtistReference> artistHistoryReferences = {
  ArtistReference.listeningHistory,
  ArtistReference.charts,
  ArtistReference.moments,
};

/// What refers to one artist, with counts for explanations.
class ArtistReferenceSummary {
  const ArtistReferenceSummary({
    required this.artistId,
    required this.name,
    this.songs = 0,
    this.albums = 0,
    this.credits = 0,
    this.projectAssignments = 0,
    this.listeningSessions = 0,
    this.qualifiedPlays = 0,
    this.chartEntries = 0,
    this.chartWeeks = 0,
    this.moments = 0,
    this.pendingCloudWrites = 0,
  });

  final String artistId;
  final String name;

  /// Songs whose primary artist this is.
  final int songs;

  /// Albums the artist owns.
  final int albums;

  /// Song credits of any role.
  final int credits;

  /// Library grouping rows (0 or 1).
  final int projectAssignments;

  /// Playback sessions, qualified or not.
  final int listeningSessions;

  /// Qualified plays (streams).
  final int qualifiedPlays;

  /// Chart entries, live or finalized.
  final int chartEntries;

  /// Distinct chart weeks among [chartEntries].
  final int chartWeeks;

  /// Moments naming the artist, as subject or related artist.
  final int moments;

  /// Artist writes or creations not yet confirmed with the cloud.
  final int pendingCloudWrites;

  /// Every kind of reference present, in [ArtistReference] terms.
  Set<ArtistReference> get references => {
    if (albums > 0) ArtistReference.albums,
    if (songs > 0) ArtistReference.songs,
    if (credits > 0) ArtistReference.credits,
    if (projectAssignments > 0) ArtistReference.projectAssignment,
    if (listeningSessions > 0 || qualifiedPlays > 0)
      ArtistReference.listeningHistory,
    if (chartEntries > 0) ArtistReference.charts,
    if (moments > 0) ArtistReference.moments,
    if (pendingCloudWrites > 0) ArtistReference.pendingCloudWrite,
  };

  ArtistLibraryState get state {
    final found = references;
    if (found.any(artistLibraryReferences.contains)) {
      return ArtistLibraryState.active;
    }
    if (found.any(artistHistoryReferences.contains)) {
      return ArtistLibraryState.retired;
    }
    if (found.contains(ArtistReference.pendingCloudWrite)) {
      return ArtistLibraryState.waitingForSync;
    }
    return ArtistLibraryState.removable;
  }
}

/// Read-only reference counts for every artist at once, for screens and
/// pickers. Runs outside any mutation; removal still re-checks with
/// [ArtistReferenceRepository] inside its own transaction.
abstract interface class ArtistReferenceSummaryRepository {
  /// One summary per stored artist, ordered by name.
  Future<List<ArtistReferenceSummary>> summarizeAll();

  /// Ids of artists in [ArtistLibraryState.retired].
  Future<Set<String>> findRetiredArtistIds();
}
