import '../metadata/metadata_field_state.dart';
import '../repositories/metadata_field_state_repository.dart';
import 'metadata_authority_policy.dart';

class MetadataFieldStateService {
  const MetadataFieldStateService({required this.repository});

  final MetadataFieldStateRepository repository;

  Future<bool> record({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
    required MetadataAuthority authority,
    required MetadataProvenanceSource source,
    required DateTime updatedAt,
    String? sourceReference,
  }) async {
    final existing = await repository.get(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
    );

    if (!MetadataAuthorityPolicy.canReplace(
      existing: existing,
      incomingAuthority: authority,
    )) {
      return false;
    }

    await repository.save(
      MetadataFieldState(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        authority: authority,
        source: source,
        sourceReference: sourceReference,
        updatedAt: updatedAt,
      ),
    );

    return true;
  }

  Future<void> recordAll({
    required MetadataEntityType entityType,
    required String entityId,
    required Iterable<String> fieldNames,
    required MetadataAuthority authority,
    required MetadataProvenanceSource source,
    required DateTime updatedAt,
    String? sourceReference,
  }) async {
    for (final fieldName in fieldNames.toSet()) {
      await record(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        authority: authority,
        source: source,
        sourceReference: sourceReference,
        updatedAt: updatedAt,
      );
    }
  }
}
