/// Permanent deletion: what a deletion would remove, computed before
/// anything is touched.
///
/// Computed read-only by SqlitePermanentDeletionImpactRepository and
/// executed by PermanentDeletionService. See
/// `_internal/APP_UPDATE_1_2_LIBRARY_DELETION_DESIGN.md`.
library;

enum PermanentDeletionTargetKind { song, album, edition, artist }

class PermanentDeletionTarget {
  const PermanentDeletionTarget.song(this.id)
    : kind = PermanentDeletionTargetKind.song;
  const PermanentDeletionTarget.album(this.id)
    : kind = PermanentDeletionTargetKind.album;
  const PermanentDeletionTarget.edition(this.id)
    : kind = PermanentDeletionTargetKind.edition;
  const PermanentDeletionTarget.artist(this.id)
    : kind = PermanentDeletionTargetKind.artist;

  final PermanentDeletionTargetKind kind;
  final String id;
}

class PermanentDeletionOptions {
  const PermanentDeletionOptions({this.includeSharedRecordings = false});

  /// Artist deletion only. When false (the default), the artist cannot be
  /// deleted while any of these exist:
  /// - a song on one of the artist's releases whose primary artist is
  ///   someone else;
  /// - a song by the artist on another artist's release.
  /// Those songs are listed in [PermanentDeletionImpact.sharedRecordingIds]
  /// so the user can confirm them explicitly.
  final bool includeSharedRecordings;
}

enum PermanentDeletionBlocker {
  /// The target id does not exist.
  notFound,

  /// Artist deletion would remove another artist's recordings, or the
  /// artist's own recordings on another artist's release, and that was not
  /// confirmed.
  sharedRecordingsNotConfirmed,

  /// A cloud write for one of the entities is still waiting to be sent.
  /// Deleting now would let the cloud keep (and later restore) a version
  /// the device no longer has.
  pendingCloudWrite,

  /// This device's library is linked to cloud sync. The cloud archive
  /// cannot delete listening history it already holds yet, so another
  /// device or a fresh install could bring it back (D10: fail closed).
  cloudSyncLinked,
}

class PlaylistDeletionImpact {
  const PlaylistDeletionImpact({
    required this.playlistId,
    required this.playlistName,
    required this.itemsRemoved,
  });

  final String playlistId;
  final String playlistName;
  final int itemsRemoved;
}

class PermanentDeletionImpact {
  const PermanentDeletionImpact({
    required this.target,
    required this.targetName,
    required this.blockers,
    required this.songIds,
    required this.albumIds,
    required this.editionIds,
    required this.artistIds,
    required this.sharedRecordingIds,
    required this.songsKeptLosingListing,
    required this.collaborationSongIdsKept,
    required this.creditLinksRemoved,
    required this.playbackSessionIds,
    required this.qualifiedPlayIds,
    required this.listeningSegmentCount,
    required this.listenedMs,
    required this.historyRowsRepointed,
    required this.chartEntryIds,
    required this.affectedChartWeeks,
    required this.momentIdsAboutTarget,
    required this.momentIdsMentioningTarget,
    required this.playlists,
    required this.mediaFileBindingCount,
    required this.lyricsCount,
    required this.metadataFieldStateCount,
    required this.artworkCropCount,
    required this.otherArtistsLosingProjectGrouping,
    required this.pendingCloudWriteCount,
    this.artworkAssetIds = const {},
    this.targetArtworkId,
  });

  final PermanentDeletionTarget target;
  final String? targetName;

  /// Empty means the deletion may proceed after the user confirms it.
  final Set<PermanentDeletionBlocker> blockers;

  // Library records that are deleted.
  final Set<String> songIds;
  final Set<String> albumIds;
  final Set<String> editionIds;
  final Set<String> artistIds;

  /// Artist deletion: recordings shared with another artist (see
  /// [PermanentDeletionOptions.includeSharedRecordings]). They are in
  /// [songIds] only when the user confirmed them.
  final Set<String> sharedRecordingIds;

  /// Edition deletion: songs that stay because another edition also lists
  /// them. Only this edition's listing is removed.
  final Set<String> songsKeptLosingListing;

  /// Artist deletion: other artists' songs on which the deleted artist was
  /// credited (co-primary, featured, guest). The songs stay; the credit
  /// keeps its printed name but loses its link to the deleted artist.
  final Set<String> collaborationSongIdsKept;
  final int creditLinksRemoved;

  // Listening history that is deleted.
  final Set<String> playbackSessionIds;
  final Set<String> qualifiedPlayIds;
  final int listeningSegmentCount;
  final int listenedMs;

  /// Edition deletion: history rows of kept songs that pointed at the
  /// deleted edition and are moved to the song's remaining home edition.
  final int historyRowsRepointed;

  // Charts and Moments.
  final Set<String> chartEntryIds;

  /// Stored weekly chart weeks (`songs:` or `albums:` + week start, UTC)
  /// whose ranks change. Every later week of the same chart type also
  /// changes (previous rank, peak, weeks on chart).
  final Set<String> affectedChartWeeks;

  /// Moments whose subject is a deleted song, release or artist.
  final Set<String> momentIdsAboutTarget;

  /// Moments about something else that name a deleted entity (the passed or
  /// displaced entity) or were caused by a deleted play.
  final Set<String> momentIdsMentioningTarget;

  // Other references.
  final List<PlaylistDeletionImpact> playlists;

  /// Library links to audio files. The files themselves are never touched.
  final int mediaFileBindingCount;
  final int lyricsCount;
  final int metadataFieldStateCount;
  final int artworkCropCount;

  /// Album deletion: other artists grouped under the deleted album as a
  /// project lose that grouping (the row cascades).
  final Set<String> otherArtistsLosingProjectGrouping;

  final int pendingCloudWriteCount;

  /// Artwork used only by the deleted records. Its library entries are
  /// removed with them; nothing else loses its picture.
  final Set<String> artworkAssetIds;

  /// The target's own artwork, for the preview.
  final String? targetArtworkId;

  bool get canProceed => blockers.isEmpty;

  /// The same impact with [blocker] added.
  PermanentDeletionImpact withBlocker(PermanentDeletionBlocker blocker) =>
      PermanentDeletionImpact(
        target: target,
        targetName: targetName,
        blockers: {...blockers, blocker},
        songIds: songIds,
        albumIds: albumIds,
        editionIds: editionIds,
        artistIds: artistIds,
        sharedRecordingIds: sharedRecordingIds,
        songsKeptLosingListing: songsKeptLosingListing,
        collaborationSongIdsKept: collaborationSongIdsKept,
        creditLinksRemoved: creditLinksRemoved,
        playbackSessionIds: playbackSessionIds,
        qualifiedPlayIds: qualifiedPlayIds,
        listeningSegmentCount: listeningSegmentCount,
        listenedMs: listenedMs,
        historyRowsRepointed: historyRowsRepointed,
        chartEntryIds: chartEntryIds,
        affectedChartWeeks: affectedChartWeeks,
        momentIdsAboutTarget: momentIdsAboutTarget,
        momentIdsMentioningTarget: momentIdsMentioningTarget,
        playlists: playlists,
        mediaFileBindingCount: mediaFileBindingCount,
        lyricsCount: lyricsCount,
        metadataFieldStateCount: metadataFieldStateCount,
        artworkCropCount: artworkCropCount,
        otherArtistsLosingProjectGrouping: otherArtistsLosingProjectGrouping,
        pendingCloudWriteCount: pendingCloudWriteCount,
        artworkAssetIds: artworkAssetIds,
        targetArtworkId: targetArtworkId,
      );

  int get qualifiedStreamCount => qualifiedPlayIds.length;

  Set<String> get allMomentIds => {
    ...momentIdsAboutTarget,
    ...momentIdsMentioningTarget,
  };

  String? get earliestAffectedWeekStartUtc {
    if (affectedChartWeeks.isEmpty) return null;
    final starts =
        affectedChartWeeks.map((w) => w.split(':').skip(1).join(':')).toList()
          ..sort();
    return starts.first;
  }
}
