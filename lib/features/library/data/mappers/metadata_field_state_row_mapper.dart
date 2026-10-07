import '../../domain/metadata/metadata_field_state.dart';

abstract final class MetadataFieldStateRowMapper {
  static Map<String, Object?> toRow(MetadataFieldState state) {
    return {
      'entity_type': state.entityType.name,
      'entity_id': state.entityId,
      'field_name': state.fieldName,
      'authority': state.authority.name,
      'source': state.source.name,
      'source_reference': state.sourceReference,
      'updated_at': state.updatedAt.toUtc().toIso8601String(),
    };
  }

  static MetadataFieldState fromRow(Map<String, Object?> row) {
    return MetadataFieldState(
      entityType: MetadataEntityType.values.byName(
        row['entity_type'] as String,
      ),
      entityId: row['entity_id'] as String,
      fieldName: row['field_name'] as String,
      authority: MetadataAuthority.values.byName(row['authority'] as String),
      source: MetadataProvenanceSource.values.byName(row['source'] as String),
      sourceReference: row['source_reference'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
