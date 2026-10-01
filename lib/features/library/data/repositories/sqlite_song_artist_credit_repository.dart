import '../../domain/entities/song_artist_credit.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../daos/song_artist_credit_dao.dart';

class SqliteSongArtistCreditRepository implements SongArtistCreditRepository {
  const SqliteSongArtistCreditRepository(this.dao);

  final SongArtistCreditDao dao;

  @override
  Future<void> create(SongArtistCredit credit) {
    return dao.insert(credit);
  }

  @override
  Future<void> save(SongArtistCredit credit) {
    return dao.update(credit);
  }

  @override
  Future<void> delete(String id) {
    return dao.delete(id);
  }

  @override
  Future<void> deleteBySongId(String songId) {
    return dao.deleteBySongId(songId);
  }

  @override
  Future<SongArtistCredit?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<SongArtistCredit>> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<List<SongArtistCredit>> getByArtistId(String artistId) {
    return dao.findByArtistId(artistId);
  }

  @override
  Future<List<SongArtistCredit>> getUnlinkedByCanonicalName(
    String canonicalName,
  ) {
    return dao.findUnlinkedByCanonicalName(canonicalName);
  }
}
