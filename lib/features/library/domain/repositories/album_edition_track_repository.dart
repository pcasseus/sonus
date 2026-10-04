import '../entities/album_edition_track.dart';

abstract interface class AlbumEditionTrackRepository {
  Future<void> create(AlbumEditionTrack membership);

  Future<void> save(AlbumEditionTrack membership);

  Future<List<AlbumEditionTrack>> getByEditionId(String editionId);

  Future<List<AlbumEditionTrack>> getBySongId(String songId);

  Future<void> delete({required String editionId, required String songId});
}
