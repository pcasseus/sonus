import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../../../library/application/repositories/library_query_repository.dart';
import '../../../../playlists/application/services/playlist_service.dart';

/// Song IDs, most recently played first, each listed once.
typedef RecentlyPlayedSongIds = Future<List<String>> Function(int limit);

/// A playlist as the car shows it.
class MediaBrowsePlaylist {
  const MediaBrowsePlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
  });

  final String id;
  final String name;
  final int trackCount;
}

/// The library reads the media browser needs. Read-only by design.
abstract interface class MediaBrowseLibrary {
  Future<List<LibraryTrack>> recentlyPlayedTracks(int limit);

  Future<List<LibraryTrack>> recentlyAddedTracks(int limit);

  Future<List<LibraryTrack>> allTracks();

  Future<List<LibraryArtist>> artists();

  Future<List<LibraryAlbum>> albums();

  Future<List<LibraryAlbum>> albumsByArtist(String artistId);

  /// The artist's catalog, in the same order the Artist Profile plays it.
  Future<List<LibraryTrack>> artistTracks(String artistId);

  /// The album's primary edition, in its saved disc and track order.
  Future<List<LibraryTrack>> albumTracks(String albumId);

  Future<List<MediaBrowsePlaylist>> playlists();

  /// The playlist in its saved order.
  Future<List<LibraryTrack>> playlistTracks(String playlistId);
}

/// [MediaBrowseLibrary] over the app's own repositories.
class RepositoryMediaBrowseLibrary implements MediaBrowseLibrary {
  RepositoryMediaBrowseLibrary({
    required this._library,
    required this._recentlyPlayedSongIds,
    this._playlists,
  });

  final LibraryQueryRepository _library;
  final RecentlyPlayedSongIds _recentlyPlayedSongIds;
  final PlaylistService? _playlists;

  @override
  Future<List<LibraryTrack>> recentlyPlayedTracks(int limit) async {
    final ids = await _recentlyPlayedSongIds(limit);
    final tracks = <LibraryTrack>[];

    for (final id in ids) {
      final track = await _library.getTrackById(id);
      if (track != null) tracks.add(track);
    }

    return tracks;
  }

  @override
  Future<List<LibraryTrack>> recentlyAddedTracks(int limit) =>
      _library.getRecentlyAddedTracks(limit);

  @override
  Future<List<LibraryTrack>> allTracks() => _library.getTracks();

  @override
  Future<List<LibraryArtist>> artists() async {
    final library = _library;
    final artists = library is StructuredArtistQueryRepository
        ? await (library as StructuredArtistQueryRepository)
              .getProfileEligibleArtists()
        : await library.getArtists();
    return artists;
  }

  @override
  Future<List<LibraryAlbum>> albums() => _library.getAlbums();

  @override
  Future<List<LibraryAlbum>> albumsByArtist(String artistId) =>
      _library.getAlbumsByArtistId(artistId);

  @override
  Future<List<LibraryTrack>> artistTracks(String artistId) =>
      _library.getTracksByArtistId(artistId);

  @override
  Future<List<LibraryTrack>> albumTracks(String albumId) async {
    final library = _library;

    if (library is AlbumEditionQueryRepository) {
      final editions = await (library as AlbumEditionQueryRepository)
          .getAlbumEditions(albumId);
      final primary =
          editions.where((edition) => edition.isPrimary).firstOrNull ??
          editions.firstOrNull;

      if (primary != null) {
        return (library as AlbumEditionQueryRepository)
            .getTracksByAlbumEditionId(primary.editionId);
      }
    }

    return library.getTracksByAlbumId(albumId);
  }

  @override
  Future<List<MediaBrowsePlaylist>> playlists() async {
    final service = _playlists;
    if (service == null) return const [];

    final summaries = await service.getPlaylists();
    return [
      for (final summary in summaries)
        MediaBrowsePlaylist(
          id: summary.playlist.id,
          name: summary.playlist.name,
          trackCount: summary.trackCount,
        ),
    ];
  }

  @override
  Future<List<LibraryTrack>> playlistTracks(String playlistId) async {
    final service = _playlists;
    if (service == null) return const [];

    final detail = await service.getPlaylist(playlistId);
    return [for (final entry in detail.tracks) entry.track];
  }
}
