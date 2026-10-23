import '../../../../core/database/app_database.dart';
import '../../domain/entities/media_file_binding.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import '../daos/media_file_binding_dao.dart';

class SqliteMediaFileBindingRepository implements MediaFileBindingRepository {
  const SqliteMediaFileBindingRepository(this.dao, {this.appDatabase});

  final MediaFileBindingDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit when a caller already owns the transaction executor.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(MediaFileBinding binding) {
    final database = appDatabase;
    if (database == null) {
      return dao.insert(binding);
    }

    return database.transaction(
      (transaction) => MediaFileBindingDao(transaction).insert(binding),
    );
  }

  @override
  Future<void> save(MediaFileBinding binding) {
    final database = appDatabase;
    if (database == null) {
      return dao.update(binding);
    }

    return database.transaction(
      (transaction) => MediaFileBindingDao(transaction).update(binding),
    );
  }

  @override
  Future<MediaFileBinding?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<MediaFileBinding?> getByNormalizedPath(String normalizedPath) {
    return dao.findByNormalizedPath(normalizedPath);
  }

  @override
  Future<List<MediaFileBinding>> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<List<MediaFileBinding>> getBySourceId(String sourceId) {
    return dao.findBySourceId(sourceId);
  }
}
