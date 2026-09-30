class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.playlistId,
    required this.songId,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String playlistId;
  final String songId;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlaylistItem copyWith({
    String? id,
    String? playlistId,
    String? songId,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlaylistItem(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      songId: songId ?? this.songId,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is PlaylistItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
