import '../models/library_album.dart';
import '../models/library_album_edition.dart';
import '../models/library_artist.dart';
import '../models/library_release_edition.dart';
import '../models/library_track.dart';
import '../models/library_track_order.dart';
import '../models/project_collaborator.dart';
import '../models/project_song_credit.dart';
import '../models/song_artist_credit_link.dart';

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

/// Every edition across the library with its song count, in one query, for
/// album-level presentation: the edition with the most songs represents
/// its release (SN-50).
abstract interface class ReleaseEditionQueryRepository {
  Future<List<LibraryReleaseEdition>> getReleaseEditions();
}

/// Every linked structured credit in the library, in one query, so
/// per-artist catalogues can be built for many artists at once.
abstract interface class SongArtistCreditLinkQueryRepository {
  Future<List<SongArtistCreditLink>> getSongArtistCreditLinks();
}

/// Credited performers by project, in one query for the whole library.
abstract interface class ProjectCollaboratorQueryRepository {
  /// Every credited performer of every album, or of [albumId] only. Shared
  /// edition memberships are counted once. Ordered by album, then lead role,
  /// song count, name and id.
  Future<List<ProjectCollaborator>> getProjectCollaborators({String? albumId});
}

/// Each structured credit on a project's songs, linked or not.
abstract interface class ProjectSongCreditQueryRepository {
  /// Every credit on the songs of [albumId] and its editions, in song and
  /// credit order. Songs without structured credits have no rows.
  Future<List<ProjectSongCredit>> getProjectSongCredits(String albumId);
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
