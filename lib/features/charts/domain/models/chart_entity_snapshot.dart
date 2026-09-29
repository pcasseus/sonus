class ChartEntitySnapshot {
  const ChartEntitySnapshot({
    required this.entityId,
    required this.title,
    required this.artistName,
    this.artistId,
    this.albumTitle,
  });

  final String entityId;
  final String title;

  /// Stable artist identity when it is known.
  ///
  /// Legacy persisted chart rows may not have this value until migrated or
  /// rebuilt. Artist/catalog achievements must never substitute artistName
  /// when this value is absent.
  final String? artistId;

  final String artistName;
  final String? albumTitle;
}
