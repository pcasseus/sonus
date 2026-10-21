enum CloudRecoveryDependencyIssueKind {
  missingReference,
  deletedReference,
  editionAlbumMismatch,
  missingStorageKey,
}

class CloudRecoveryDependencyIssue {
  const CloudRecoveryDependencyIssue({
    required this.kind,
    required this.entityId,
    required this.fieldName,
    this.referencedId,
  });

  final CloudRecoveryDependencyIssueKind kind;
  final String entityId;
  final String fieldName;
  final String? referencedId;
}
