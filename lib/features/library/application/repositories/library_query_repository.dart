import '../models/library_album.dart';
import '../models/library_album_edition.dart';
import '../models/library_artist.dart';
import '../models/library_track.dart';
import '../models/library_track_order.dart';
import '../models/project_collaborator.dart';

abstract interface class LibraryQueryRepository {
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  });

  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit);

  Future<LibraryTrack?> getTrackById(String songId);

  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  });

  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId);

  Future<List<LibraryAlbum>> getAlbums();

  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit);

  Future<LibraryAlbum?> getAlbumById(String albumId);

  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId);

  Future<List<LibraryArtist>> getArtists();

  Future<LibraryArtist?> getArtistById(String artistId);
}

abstract interface class AlbumEditionQueryRepository {
  Future<List<LibraryAlbumEdition>> getAlbumEditions(String albumId);

  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId);
}

/// Credited performers by project, in one query for the whole library.
abstract interface class ProjectCollaboratorQueryRepository {
  /// Every credited performer of every album, or of [albumId] only. Shared
  /// edition memberships are counted once. Ordered by album, then lead role,
  /// song count, name and id.
  Future<List<ProjectCollaborator>> getProjectCollaborators({String? albumId});
}

abstract interface class StructuredArtistQueryRepository {
  Future<List<LibraryArtist>> getProfileEligibleArtists();

  Future<LibraryArtist?> getProfileEligibleArtistById(String artistId);

  Future<List<LibraryTrack>> getMainTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  });

  Future<List<LibraryTrack>> getCollaborationTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  });
}
