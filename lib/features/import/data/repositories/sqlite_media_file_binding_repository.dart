import '../../domain/entities/media_file_binding.dart';
import '../../domain/repositories/media_file_binding_repository.dart';
import '../daos/media_file_binding_dao.dart';

class SqliteMediaFileBindingRepository implements MediaFileBindingRepository {
  const SqliteMediaFileBindingRepository(this.dao);

  final MediaFileBindingDao dao;

  @override
  Future<void> create(MediaFileBinding binding) {
    return dao.insert(binding);
  }

  @override
  Future<void> save(MediaFileBinding binding) {
    return dao.update(binding);
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
}
