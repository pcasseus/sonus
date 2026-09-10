enum ImportFailureType {
  fileMissing,
  unsupportedFormat,
  metadataUnreadable,
  invalidMetadata,
  duplicatePath,
  ambiguousFileBinding,
  persistenceFailure,
  unknown,
}

class ImportFailure {
  const ImportFailure({required this.type, required this.message});

  final ImportFailureType type;
  final String message;
}
