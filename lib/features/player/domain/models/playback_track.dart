class PlaybackTrack {
  const PlaybackTrack({
    required this.songId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.filePath,
    required this.duration,
  });

  final String songId;
  final String title;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final String filePath;
  final Duration duration;

  bool get hasPlayablePath => filePath.trim().isNotEmpty;

  PlaybackTrack copyWith({
    String? songId,
    String? title,
    String? artistId,
    String? artistName,
    String? albumId,
    String? albumTitle,
    String? filePath,
    Duration? duration,
  }) {
    return PlaybackTrack(
      songId: songId ?? this.songId,
      title: title ?? this.title,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      albumId: albumId ?? this.albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackTrack && other.songId == songId;
  }

  @override
  int get hashCode => songId.hashCode;
}
