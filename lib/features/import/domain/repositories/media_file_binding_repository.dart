import '../entities/media_file_binding.dart';

abstract interface class MediaFileBindingRepository {
  Future<void> create(MediaFileBinding binding);

  Future<void> save(MediaFileBinding binding);

  Future<MediaFileBinding?> getById(String id);

  Future<MediaFileBinding?> getByNormalizedPath(String normalizedPath);

  Future<List<MediaFileBinding>> getBySongId(String songId);

  Future<List<MediaFileBinding>> getBySourceId(String sourceId);
}
