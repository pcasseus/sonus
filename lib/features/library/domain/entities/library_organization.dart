/// What kind of release an album is. Unclassified albums have none.
enum ReleaseKind {
  soundtrack,
  castRecording,
  compilation;

  /// The kind a MusicBrainz release group's secondary types state, if any.
  /// MusicBrainz has no cast-recording type; those come from the user.
  static ReleaseKind? fromMusicBrainz(Iterable<String> secondaryTypes) {
    final types = {
      for (final type in secondaryTypes) type.trim().toLowerCase(),
    };

    if (types.contains('soundtrack')) {
      return ReleaseKind.soundtrack;
    }
    if (types.contains('compilation')) {
      return ReleaseKind.compilation;
    }
    return null;
  }
}

/// Where a classification came from: an external source such as a
/// MusicBrainz release-group type, or the user.
enum ReleaseClassificationAuthority { external, manual }

/// A release's format. A release without a stated format is an Album.
enum ReleaseFormat {
  single,
  ep,
  album;

  /// The format a MusicBrainz release group's primary type states, if it
  /// is one of these. "Broadcast" and "Other" state none.
  static ReleaseFormat? fromMusicBrainz(String? primaryType) =>
      switch (primaryType?.trim().toLowerCase()) {
        'single' => ReleaseFormat.single,
        'ep' => ReleaseFormat.ep,
        'album' => ReleaseFormat.album,
        _ => null,
      };

  /// "Single", "EP" or "Album".
  String get label => switch (this) {
    ReleaseFormat.single => 'Single',
    ReleaseFormat.ep => 'EP',
    ReleaseFormat.album => 'Album',
  };

  /// Singles chart through their songs only, never as a release.
  bool get chartsAsRelease => this != ReleaseFormat.single;
}

/// A release's stated format and who stated it.
class AlbumReleaseFormat {
  const AlbumReleaseFormat({
    required this.albumId,
    required this.format,
    required this.authority,
    required this.createdAt,
    required this.updatedAt,
    this.sourceReference,
  });

  final String albumId;
  final ReleaseFormat format;
  final ReleaseClassificationAuthority authority;

  /// For external formats, e.g. `musicbrainz:release-group:<id>`.
  final String? sourceReference;

  final DateTime createdAt;
  final DateTime updatedAt;
}

class AlbumReleaseClassification {
  const AlbumReleaseClassification({
    required this.albumId,
    required this.kind,
    required this.authority,
    required this.createdAt,
    required this.updatedAt,
    this.sourceReference,
  });

  final String albumId;
  final ReleaseKind kind;
  final ReleaseClassificationAuthority authority;

  /// For external classifications, e.g. `musicbrainz:release-group:<id>`.
  final String? sourceReference;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soundtracks and cast recordings are projects whose performers can be
  /// shown under the project. Compilations gather independent artists, so
  /// they never group anyone automatically.
  bool get groupsPerformers =>
      kind == ReleaseKind.soundtrack || kind == ReleaseKind.castRecording;
}

/// A user's choice of where an artist appears in the Library.
enum ArtistProjectAssignmentMode {
  /// Shown under a project's collaborators instead of as a Library entry.
  grouped,

  /// Always its own Library entry, even if it would be grouped otherwise.
  standalone,
}

class ArtistProjectAssignment {
  const ArtistProjectAssignment({
    required this.artistId,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    this.albumId,
  });

  final String artistId;
  final ArtistProjectAssignmentMode mode;

  /// The project, when [mode] is grouped.
  final String? albumId;

  final DateTime createdAt;
  final DateTime updatedAt;
}
