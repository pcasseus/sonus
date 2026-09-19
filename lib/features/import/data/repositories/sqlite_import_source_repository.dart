import '../../domain/entities/import_source.dart';
import '../../domain/repositories/import_source_repository.dart';
import '../daos/import_source_dao.dart';

class SqliteImportSourceRepository implements ImportSourceRepository {
  const SqliteImportSourceRepository(this.dao);

  final ImportSourceDao dao;

  @override
  Future<void> create(ImportSource source) {
    return dao.insert(source);
  }

  @override
  Future<void> save(ImportSource source) {
    return dao.update(source);
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
