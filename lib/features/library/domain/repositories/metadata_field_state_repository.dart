import '../metadata/metadata_field_state.dart';

abstract interface class MetadataFieldStateRepository {
  Future<MetadataFieldState?> get({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  });

  Future<List<MetadataFieldState>> getByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  });

  Future<void> save(MetadataFieldState state);

  Future<void> delete({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  });

  Future<void> deleteByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  });
}
