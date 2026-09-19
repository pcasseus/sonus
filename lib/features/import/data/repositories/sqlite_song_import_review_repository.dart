import '../../domain/entities/song_import_review.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../daos/song_import_review_dao.dart';

class SqliteSongImportReviewRepository
    implements SongImportReviewRepository {
  const SqliteSongImportReviewRepository(this.dao);

  final SongImportReviewDao dao;

  @override
  Future<void> create(SongImportReview review) {
    return dao.insert(review);
  }

  @override
  Future<void> save(SongImportReview review) {
    return dao.update(review);
  }

  @override
  Future<SongImportReview?> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<List<SongImportReview>> getUnresolved() {
    return dao.findUnresolved();
  }

  @override
  Future<int> countUnresolved() {
    return dao.countUnresolved();
  }
}
