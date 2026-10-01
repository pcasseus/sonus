import '../models/library_album.dart';
import '../models/library_artist.dart';
import '../models/library_track.dart';
import '../models/library_track_order.dart';

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
