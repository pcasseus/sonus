/// How one folder's songs are filed (SN-45): every song in the folder joins
/// one album, whatever the individual files' album or artist tags say.
///
/// Only the album's title and owner come from the folder. Each song keeps
/// its own performer, featured artists, disc and track number.
class ImportFolderPlacement {
  const ImportFolderPlacement({
    required this.folderKey,
    required this.albumTitle,
    required this.albumArtistName,
  });

  /// See SourceFolderKey.
  final String folderKey;
  final String albumTitle;
  final String albumArtistName;

  @override
  bool operator ==(Object other) =>
      other is ImportFolderPlacement &&
      other.folderKey == folderKey &&
      other.albumTitle == albumTitle &&
      other.albumArtistName == albumArtistName;

  @override
  int get hashCode => Object.hash(folderKey, albumTitle, albumArtistName);

  @override
  String toString() =>
      'ImportFolderPlacement($folderKey: "$albumTitle" by $albumArtistName)';
}
