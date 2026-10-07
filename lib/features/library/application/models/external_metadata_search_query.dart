enum ExternalMetadataEntityKind { artist, album, track }

class ExternalMetadataSearchQuery {
  const ExternalMetadataSearchQuery({
    required this.entityKind,
    this.title,
    this.artistName,
    this.albumTitle,
    this.durationSeconds,
    this.limit = 10,
  });

  final ExternalMetadataEntityKind entityKind;
  final String? title;
  final String? artistName;
  final String? albumTitle;
  final int? durationSeconds;
  final int limit;

  bool get isBlank {
    return _isBlank(title) && _isBlank(artistName) && _isBlank(albumTitle);
  }

  static bool _isBlank(String? value) {
    return value == null || value.trim().isEmpty;
  }
}
