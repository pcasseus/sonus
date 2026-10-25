import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';

/// A song in an artist's Top Tracks with its all-time qualified streams.
class ArtistTopTrack {
  const ArtistTopTrack({required this.track, required this.streamCount});

  final LibraryTrack track;
  final int streamCount;
}

/// Someone credited as primary artist on a track of a project (an album
/// owned by the profile's artist), with the tracks they perform there.
class ArtistProfileCollaborator {
  const ArtistProfileCollaborator({
    required this.artistId,
    required this.name,
    required this.tracks,
    this.artworkPath,
  });

  final String artistId;
  final String name;
  final String? artworkPath;
  final List<LibraryTrack> tracks;
}

/// Presentation-only derivations for the Artist Profile sections. They read
/// structured identities (song and album artist IDs, the existing qualified
/// play ranking) and never compare names.
abstract final class ArtistProfileSections {
  static const int topTrackLimit = 5;

  /// The catalogue's most streamed songs, in the ranking's order (streams,
  /// then most recent stream, then ID). Blacklisted songs are left out;
  /// unavailable ones stay, so history is not rewritten. Songs never
  /// streamed are not ranked, so no count is ever invented.
  static List<ArtistTopTrack> topTracks({
    required Iterable<LibraryTrack> catalogue,
    required Iterable<AnalyticsRankedEntity> rankedSongs,
    int limit = topTrackLimit,
  }) {
    final bySongId = {
      for (final track in catalogue)
        if (!track.isBlocked) track.songId: track,
    };
    final result = <ArtistTopTrack>[];

    for (final ranked in rankedSongs) {
      final track = bySongId[ranked.entityId];
      if (track == null || ranked.qualifiedStreamCount <= 0) continue;
      result.add(
        ArtistTopTrack(track: track, streamCount: ranked.qualifiedStreamCount),
      );
      if (result.length == limit) break;
    }

    return List.unmodifiable(result);
  }

  /// Songs the artist collaborated on: featured and guest credits, plus
  /// main (primary or co-primary) credits on a release another artist owns,
  /// such as a duet on someone else's album or a soundtrack contribution.
  static List<LibraryTrack> collaborations({
    required Iterable<LibraryTrack> mainTracks,
    required Iterable<LibraryTrack> featuredTracks,
    required Set<String> ownedAlbumIds,
  }) {
    final seen = <String>{};
    final result = <LibraryTrack>[];

    for (final track in [
      ...featuredTracks,
      ...mainTracks.where((track) => !ownedAlbumIds.contains(track.albumId)),
    ]) {
      if (seen.add(track.songId)) result.add(track);
    }

    result.sort((a, b) {
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return byTitle != 0 ? byTitle : a.songId.compareTo(b.songId);
    });

    return List.unmodifiable(result);
  }

  /// Each primary artist of the project's tracks, once, other than the
  /// project's own artist; ordered by how many tracks they perform, then
  /// name, then ID.
  static List<ArtistProfileCollaborator> collaborators({
    required String projectArtistId,
    required Iterable<LibraryTrack> projectTracks,
    required Map<String, LibraryArtist> artistsById,
  }) {
    final tracksByArtist = <String, List<LibraryTrack>>{};
    final seenSongs = <String>{};

    for (final track in projectTracks) {
      if (track.artistId == projectArtistId || !seenSongs.add(track.songId)) {
        continue;
      }
      tracksByArtist.putIfAbsent(track.artistId, () => []).add(track);
    }

    final result = [
      for (final MapEntry(key: artistId, value: tracks)
          in tracksByArtist.entries)
        ArtistProfileCollaborator(
          artistId: artistId,
          name: artistsById[artistId]?.name ?? tracks.first.artistName,
          artworkPath: _artworkPath(artistsById[artistId]),
          tracks: List.unmodifiable(tracks),
        ),
    ];

    result.sort((a, b) {
      final byCount = b.tracks.length.compareTo(a.tracks.length);
      if (byCount != 0) return byCount;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.artistId.compareTo(b.artistId);
    });

    return List.unmodifiable(result);
  }

  static String? _artworkPath(LibraryArtist? artist) {
    for (final path in [
      artist?.topArtistsArtworkPath,
      artist?.headerArtworkPath,
    ]) {
      final trimmed = path?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
