import '../../../search/application/models/library_search_results.dart';
import '../../../search/application/repositories/library_search_repository.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../application/repositories/library_query_repository.dart';
import '../daos/library_query_dao.dart';

class SqliteLibraryQueryRepository
    implements
        LibraryQueryRepository,
        StructuredArtistQueryRepository,
        LibrarySearchRepository {
  const SqliteLibraryQueryRepository(this.dao);

  final LibraryQueryDao dao;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    return dao.findTracks(order: order);
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) {
    return dao.findRecentlyAddedTracks(limit);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    return dao.findTrackById(songId);
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    return dao.findTracksByArtistId(artistId, order: order);
  }

  @override
  Future<List<LibraryArtist>> getProfileEligibleArtists() {
    return dao.findProfileEligibleArtists();
  }

  @override
  Future<LibraryArtist?> getProfileEligibleArtistById(String artistId) {
    return dao.findProfileEligibleArtistById(artistId);
  }

  @override
  Future<List<LibraryTrack>> getMainTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    return dao.findMainTracksByArtistId(artistId, order: order);
  }

  @override
  Future<List<LibraryTrack>> getCollaborationTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    return dao.findCollaborationTracksByArtistId(artistId, order: order);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) {
    return dao.findTracksByAlbumId(albumId);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() {
    return dao.findAlbums();
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) {
    return dao.findRecentlyAddedAlbums(limit);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    return dao.findAlbumById(albumId);
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) {
    return dao.findAlbumsByArtistId(artistId);
  }

  @override
  Future<List<LibraryArtist>> getArtists() {
    return dao.findArtists();
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    return dao.findArtistById(artistId);
  }

  @override
  Future<LibrarySearchResults> search(String query) {
    return dao.search(query);
  }
}
