import '../entities/import_batch_record.dart';

abstract interface class ImportBatchRepository {
  Future<void> create(ImportBatchRecord batch);
  Future<void> save(ImportBatchRecord batch);
  Future<ImportBatchRecord?> getById(String id);
  Future<List<ImportBatchRecord>> getAll();
}
