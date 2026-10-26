import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/project_collaborator.dart';
import '../../domain/entities/song_artist_credit.dart';

/// A song in an artist's Top Tracks with its all-time qualified streams.
class ArtistTopTrack {
  const ArtistTopTrack({required this.track, required this.streamCount});

  final LibraryTrack track;
  final int streamCount;
}

/// Someone credited on a project (an album owned by the profile's artist),
/// with the tracks they lead there.
class ArtistProfileCollaborator {
  const ArtistProfileCollaborator({
    required this.artistId,
    required this.name,
    required this.tracks,
    this.artworkPath,
    this.roles = const {},
    this.songCount,
  });

  final String artistId;
  final String name;
  final String? artworkPath;

  /// The songs they lead on the project, for playing them here.
  final List<LibraryTrack> tracks;

  /// Every credited role, from the structured credits; empty when only the
  /// songs' lead artists are known.
  final Set<SongArtistCreditRole> roles;

  /// Distinct project songs they are credited on, in any role.
  final int? songCount;

  int get displaySongCount => songCount ?? tracks.length;

  /// The most prominent role, primary first, if known.
  SongArtistCreditRole? get leadRole => roles.isEmpty
      ? null
      : SongArtistCreditRole.values.firstWhere(roles.contains);
}

/// A project a contributor appears on: the releases one owner (such as a
/// soundtrack's cast) owns, with the contributor's songs on them.
class ContributorAppearance {
  const ContributorAppearance({
    required this.ownerArtistId,
    required this.ownerName,
    required this.albums,
    required this.tracks,
  });

  final String ownerArtistId;
  final String ownerName;

  /// The owner's releases the contributor is on, newest first.
  final List<LibraryAlbum> albums;

  /// The contributor's songs there, in release then track order.
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
  /// The artist's place in [rankedArtists] (all-time, most streamed
  /// first), or null when they have no qualified streams.
  static ArtistStanding? standing({
    required String artistId,
    required List<AnalyticsRankedEntity> rankedArtists,
  }) {
    final index = rankedArtists.indexWhere(
      (ranked) => ranked.entityId == artistId,
    );
    if (index == -1) return null;

    final streams = rankedArtists[index].qualifiedStreamCount;
    return streams <= 0
        ? null
        : ArtistStanding(rank: index + 1, streamCount: streams);
  }

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
  /// With [albumsById], newest release first; otherwise by title.
  static List<LibraryTrack> collaborations({
    required Iterable<LibraryTrack> mainTracks,
    required Iterable<LibraryTrack> featuredTracks,
    required Set<String> ownedAlbumIds,
    Map<String, LibraryAlbum>? albumsById,
  }) {
    final seen = <String>{};
    final result = <LibraryTrack>[];

    for (final track in [
      ...featuredTracks,
      ...mainTracks.where((track) => !ownedAlbumIds.contains(track.albumId)),
    ]) {
      if (seen.add(track.songId)) result.add(track);
    }

    if (albumsById == null) {
      result.sort((a, b) {
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return byTitle != 0 ? byTitle : a.songId.compareTo(b.songId);
      });
    } else {
      result.sort((a, b) => compareByRelease(a, b, albumsById));
    }

    return List.unmodifiable(result);
  }

  /// Releases newest first by release date; undated releases last. A
  /// partial date sorts by its start (`2026` with `2026-01-01`), the less
  /// exact one after. Ties fall back to title, then ID, so the order never
  /// shifts.
  static int compareReleases(LibraryAlbum a, LibraryAlbum b) {
    final aDate = a.releaseDateValue;
    final bDate = b.releaseDateValue;
    if (aDate != null && bDate != null) {
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
    } else if (aDate != null || bDate != null) {
      return aDate == null ? 1 : -1;
    }
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.albumId.compareTo(b.albumId);
  }

  /// Songs by their release (newest first), then disc and track.
  static int compareByRelease(
    LibraryTrack a,
    LibraryTrack b,
    Map<String, LibraryAlbum> albumsById,
  ) {
    if (a.albumId != b.albumId) {
      final aAlbum = albumsById[a.albumId];
      final bAlbum = albumsById[b.albumId];
      if (aAlbum != null && bAlbum != null) {
        return compareReleases(aAlbum, bAlbum);
      }
      if (aAlbum != null || bAlbum != null) return aAlbum == null ? 1 : -1;
      return a.albumId.compareTo(b.albumId);
    }
    for (final comparison in [
      a.discNumber.compareTo(b.discNumber),
      a.trackNumber.compareTo(b.trackNumber),
      a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      a.songId.compareTo(b.songId),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  /// Where a contributor (an artist with no release of its own) appears:
  /// one entry per release owner, the main project (most songs) first.
  /// With [projectArtistId], only that project.
  static List<ContributorAppearance> appearances({
    required Iterable<LibraryTrack> tracks,
    required Map<String, LibraryAlbum> albumsById,
    String? projectArtistId,
  }) {
    final byOwner = <String, List<LibraryTrack>>{};
    final seen = <String>{};

    for (final track in tracks) {
      final album = albumsById[track.albumId];
      if (album == null || !seen.add(track.songId)) continue;
      if (projectArtistId != null && album.artistId != projectArtistId) {
        continue;
      }
      byOwner.putIfAbsent(album.artistId, () => []).add(track);
    }

    final result = [
      for (final MapEntry(key: ownerId, value: ownerTracks) in byOwner.entries)
        ContributorAppearance(
          ownerArtistId: ownerId,
          ownerName: albumsById[ownerTracks.first.albumId]!.artistName,
          albums: List.unmodifiable(
            {
              for (final track in ownerTracks)
                track.albumId: albumsById[track.albumId]!,
            }.values.toList()..sort(compareReleases),
          ),
          tracks: List.unmodifiable(
            ownerTracks..sort((a, b) => compareByRelease(a, b, albumsById)),
          ),
        ),
    ];

    result.sort((a, b) {
      final bySongs = b.tracks.length.compareTo(a.tracks.length);
      if (bySongs != 0) return bySongs;
      final byName = a.ownerName.toLowerCase().compareTo(
        b.ownerName.toLowerCase(),
      );
      return byName != 0 ? byName : a.ownerArtistId.compareTo(b.ownerArtistId);
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

  /// Every performer credited on the artist's projects, from the structured
  /// credit query (any role: primary, co-primary, featured or guest), each
  /// once across the projects. Ordered by most prominent role, then songs,
  /// then name, then ID. Play uses the songs they lead on the projects.
  static List<ArtistProfileCollaborator> structuredCollaborators({
    required String projectArtistId,
    required Iterable<ProjectCollaborator> credits,
    required Iterable<LibraryTrack> projectTracks,
    required Map<String, LibraryArtist> artistsById,
  }) {
    final roles = <String, Set<SongArtistCreditRole>>{};
    final counts = <String, int>{};
    final names = <String, String>{};

    for (final credit in credits) {
      if (credit.artistId == projectArtistId) continue;
      roles.putIfAbsent(credit.artistId, () => {}).addAll(credit.roles);
      counts[credit.artistId] =
          (counts[credit.artistId] ?? 0) + credit.songCount;
      names.putIfAbsent(credit.artistId, () => credit.artistName);
    }

    final led = <String, List<LibraryTrack>>{};
    final seen = <String>{};
    for (final track in projectTracks) {
      if (roles.containsKey(track.artistId) && seen.add(track.songId)) {
        led.putIfAbsent(track.artistId, () => []).add(track);
      }
    }

    final result = [
      for (final MapEntry(key: artistId, value: artistRoles) in roles.entries)
        ArtistProfileCollaborator(
          artistId: artistId,
          name: artistsById[artistId]?.name ?? names[artistId] ?? artistId,
          artworkPath: _artworkPath(artistsById[artistId]),
          tracks: List.unmodifiable(led[artistId] ?? const <LibraryTrack>[]),
          roles: Set.unmodifiable(artistRoles),
          songCount: counts[artistId],
        ),
    ];

    int roleRank(ArtistProfileCollaborator c) =>
        c.leadRole?.index ?? SongArtistCreditRole.values.length;

    result.sort((a, b) {
      final byRole = roleRank(a).compareTo(roleRank(b));
      if (byRole != 0) return byRole;
      final byCount = b.displaySongCount.compareTo(a.displaySongCount);
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

/// Where an artist stands in the listener's all-time artist ranking.
class ArtistStanding {
  const ArtistStanding({
    required this.rank,
    required this.streamCount,
    this.listened,
  });

  final int rank;
  final int streamCount;

  /// All-time listening time credited to the artist, when it is known.
  final Duration? listened;

  /// "Your #1 artist" or "Ranked #6 among your artists".
  String get rankLabel =>
      rank == 1 ? 'Your #1 artist' : 'Ranked #$rank among your artists';

  ArtistStanding withListened(Duration? listened) =>
      ArtistStanding(rank: rank, streamCount: streamCount, listened: listened);

  @override
  bool operator ==(Object other) =>
      other is ArtistStanding &&
      other.rank == rank &&
      other.streamCount == streamCount &&
      other.listened == listened;

  @override
  int get hashCode => Object.hash(rank, streamCount, listened);
}
