import '../../domain/metadata/metadata_field_state.dart';
import '../../domain/repositories/metadata_field_state_repository.dart';
import '../daos/metadata_field_state_dao.dart';

class SqliteMetadataFieldStateRepository
    implements MetadataFieldStateRepository {
  const SqliteMetadataFieldStateRepository(this.dao);

  final MetadataFieldStateDao dao;

  @override
  Future<MetadataFieldState?> get({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) {
    return dao.find(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );
  }

  @override
  Future<List<MetadataFieldState>> getByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) {
    return dao.findByEntity(entityType: entityType, entityId: entityId);
  }

  @override
  Future<void> save(MetadataFieldState state) {
    return dao.upsert(state);
  }

  @override
  Future<void> delete({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) {
    return dao.delete(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );
  }

  @override
  Future<void> deleteByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) {
    return dao.deleteByEntity(entityType: entityType, entityId: entityId);
  }
}
