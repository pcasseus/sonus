import '../entities/song_import_review.dart';

abstract interface class SongImportReviewRepository {
  Future<void> create(SongImportReview review);

  Future<void> save(SongImportReview review);

  Future<SongImportReview?> getBySongId(String songId);

  Future<List<SongImportReview>> getUnresolved();

  Future<int> countUnresolved();
}
