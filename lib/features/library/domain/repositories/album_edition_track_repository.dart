import '../entities/album_edition_track.dart';

abstract interface class AlbumEditionTrackRepository {
  Future<void> create(AlbumEditionTrack membership);

  Future<void> save(AlbumEditionTrack membership);

  Future<List<AlbumEditionTrack>> getByEditionId(String editionId);

  Future<List<AlbumEditionTrack>> getBySongId(String songId);

  Future<void> delete({required String editionId, required String songId});
}

/// Optional read-only capability: the songs listed on at least one edition
/// other than their home edition, i.e. with a placement that travels with
/// the song's cloud record (SN-50 BLOCKED #4). Sorted, no duplicates.
abstract interface class AwayFromHomeListings {
  Future<List<String>> songIdsListedAwayFromHome();
}
