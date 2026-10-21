enum BackupFailureCode {
  missingArtwork,
  invalidArtwork,
  artworkChanged,
  publicationFailed,
}

/// A typed backup failure the recovery UI can explain to the user.
///
/// Extends [FormatException] so existing callers that treat backup
/// content failures as format errors keep their behavior.
class BackupException extends FormatException {
  BackupException(
    this.code,
    super.message, {
    List<String> artworkIds = const [],
  }) : artworkIds = List.unmodifiable(artworkIds);

  final BackupFailureCode code;

  // Artwork identities involved in the failure, when applicable.
  final List<String> artworkIds;
}

/// Raised when publication would replace an existing file.
class BackupDestinationExistsError extends StateError {
  BackupDestinationExistsError([
    super.message = 'Backup destination already exists.',
  ]);
}
