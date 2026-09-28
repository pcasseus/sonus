class ChartEntitySnapshot {
  const ChartEntitySnapshot({
    required this.entityId,
    required this.title,
    required this.artistName,
    this.albumTitle,
  });

  final String entityId;
  final String title;
  final String artistName;
  final String? albumTitle;
}
