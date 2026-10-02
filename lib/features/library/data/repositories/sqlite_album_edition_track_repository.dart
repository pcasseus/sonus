import '../../domain/entities/album_edition_track.dart';
import '../../domain/repositories/album_edition_track_repository.dart';
import '../daos/album_edition_track_dao.dart';

class SqliteAlbumEditionTrackRepository implements AlbumEditionTrackRepository {
  const SqliteAlbumEditionTrackRepository(this.dao);

  final AlbumEditionTrackDao dao;

  @override
  Future<void> create(AlbumEditionTrack membership) {
    return dao.insert(membership);
  }

  @override
  Future<void> save(AlbumEditionTrack membership) {
    return dao.update(membership);
  }

  @override
  Future<List<AlbumEditionTrack>> getByEditionId(String editionId) {
    return dao.findByEditionId(editionId);
  }

  @override
  Future<List<AlbumEditionTrack>> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<void> delete({required String editionId, required String songId}) {
    return dao.delete(editionId: editionId, songId: songId);
  }
}
