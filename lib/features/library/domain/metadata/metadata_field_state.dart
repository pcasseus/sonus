enum MetadataEntityType { artist, album, albumEdition, song }

enum MetadataAuthority { inferred, imported, external, confirmed, manual }

enum MetadataProvenanceSource {
  filename,
  embeddedTag,
  musicBrainz,
  coverArtArchive,
  review,
  user,
  legacy,
}

class MetadataFieldState {
  const MetadataFieldState({
    required this.entityType,
    required this.entityId,
    required this.fieldName,
    required this.authority,
    required this.source,
    required this.updatedAt,
    this.sourceReference,
  });

  final MetadataEntityType entityType;
  final String entityId;
  final String fieldName;
  final MetadataAuthority authority;
  final MetadataProvenanceSource source;
  final String? sourceReference;
  final DateTime updatedAt;

  MetadataFieldState copyWith({
    MetadataEntityType? entityType,
    String? entityId,
    String? fieldName,
    MetadataAuthority? authority,
    MetadataProvenanceSource? source,
    Object? sourceReference = _unset,
    DateTime? updatedAt,
  }) {
    return MetadataFieldState(
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      fieldName: fieldName ?? this.fieldName,
      authority: authority ?? this.authority,
      source: source ?? this.source,
      sourceReference: identical(sourceReference, _unset)
          ? this.sourceReference
          : sourceReference as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MetadataFieldState &&
            other.entityType == entityType &&
            other.entityId == entityId &&
            other.fieldName == fieldName;
  }

  @override
  int get hashCode => Object.hash(entityType, entityId, fieldName);
}
