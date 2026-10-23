import '../../../../core/database/app_database.dart';
import '../../domain/entities/import_batch_record.dart';
import '../../domain/repositories/import_batch_repository.dart';
import '../daos/import_batch_dao.dart';

class SqliteImportBatchRepository implements ImportBatchRepository {
  const SqliteImportBatchRepository(this.dao, {this.appDatabase});

  final ImportBatchDao dao;

  /// When provided, production writes participate in restore admission.
  /// The raw DAO remains available for transaction-owned and isolated uses.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(ImportBatchRecord batch) {
    final database = appDatabase;
    if (database == null) {
      return dao.insert(batch);
    }

    return database.transaction(
      (transaction) => ImportBatchDao(transaction).insert(batch),
    );
  }

  @override
  Future<void> save(ImportBatchRecord batch) {
    final database = appDatabase;
    if (database == null) {
      return dao.update(batch);
    }

    return database.transaction(
      (transaction) => ImportBatchDao(transaction).update(batch),
    );
  }

  @override
  Future<ImportBatchRecord?> getById(String id) {
    return dao.findById(id);
  }

  @override
  Future<List<ImportBatchRecord>> getAll() {
    return dao.findAll();
  }
}
