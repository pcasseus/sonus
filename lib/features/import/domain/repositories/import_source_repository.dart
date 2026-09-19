import '../entities/import_source.dart';

abstract interface class ImportSourceRepository {
  Future<void> create(ImportSource source);

  Future<void> save(ImportSource source);

  Future<ImportSource?> getById(String id);

  Future<ImportSource?> getByNormalizedRootPath(String normalizedRootPath);

  Future<List<ImportSource>> getAll();
}
