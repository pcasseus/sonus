import '../../../../core/database/app_database.dart';
import '../../domain/entities/song_import_review.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../daos/song_import_review_dao.dart';

class SqliteSongImportReviewRepository implements SongImportReviewRepository {
  const SqliteSongImportReviewRepository(this.dao, {this.appDatabase});

  final SongImportReviewDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit when a caller already owns the transaction.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(SongImportReview review) {
    final database = appDatabase;
    if (database == null) {
      return dao.insert(review);
    }

    return database.transaction(
      (transaction) => SongImportReviewDao(transaction).insert(review),
    );
  }

  @override
  Future<void> save(SongImportReview review) {
    final database = appDatabase;
    if (database == null) {
      return dao.update(review);
    }

    return database.transaction(
      (transaction) => SongImportReviewDao(transaction).update(review),
    );
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
