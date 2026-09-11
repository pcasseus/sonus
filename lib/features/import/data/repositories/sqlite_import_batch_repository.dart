import '../../domain/entities/import_batch_record.dart';
import '../../domain/repositories/import_batch_repository.dart';
import '../daos/import_batch_dao.dart';

class SqliteImportBatchRepository implements ImportBatchRepository {
  const SqliteImportBatchRepository(this.dao);

  final ImportBatchDao dao;

  @override
  Future<void> create(ImportBatchRecord batch) {
    return dao.insert(batch);
  }

  @override
  Future<void> save(ImportBatchRecord batch) {
    return dao.update(batch);
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
