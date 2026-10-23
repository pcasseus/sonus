import '../../../../core/database/app_database.dart';
import '../../domain/entities/import_source.dart';
import '../../domain/repositories/import_source_repository.dart';
import '../daos/import_source_dao.dart';

class SqliteImportSourceRepository implements ImportSourceRepository {
  const SqliteImportSourceRepository(this.dao, {this.appDatabase});

  final ImportSourceDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit when a caller already owns the transaction executor.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(ImportSource source) {
    final database = appDatabase;
    if (database == null) {
      return dao.insert(source);
    }

    return database.transaction(
      (transaction) => ImportSourceDao(transaction).insert(source),
    );
  }

  @override
  Future<void> save(ImportSource source) {
    final database = appDatabase;
    if (database == null) {
      return dao.update(source);
    }

    return database.transaction(
      (transaction) => ImportSourceDao(transaction).update(source),
    );
  }

  @override
  Future<ImportSource?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<ImportSource?> getByNormalizedRootPath(String normalizedRootPath) {
    return dao.findByNormalizedRootPath(normalizedRootPath);
  }

  @override
  Future<List<ImportSource>> getAll() {
    return dao.findAll();
  }
}
