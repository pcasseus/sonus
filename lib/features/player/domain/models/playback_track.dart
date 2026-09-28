class PlaybackTrack {
  static const Object _unset = Object();

  const PlaybackTrack({
    required this.songId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.filePath,
    required this.duration,
    this.albumEditionId,
    this.albumEditionTitle,
    this.artworkId,
    this.artworkPath,
    this.isSongBlocked = false,
  });

  final String songId;
  final String title;

  final String artistId;
  final String artistName;

  final String albumId;
  final String albumTitle;

  final String? albumEditionId;
  final String? albumEditionTitle;

  final String? artworkId;
  final String? artworkPath;

  final String filePath;
  final Duration duration;

  final bool isSongBlocked;

  bool get isBlocked => isSongBlocked;

  bool get hasPlayablePath => filePath.trim().isNotEmpty;

  bool get hasArtworkPath =>
      artworkPath != null && artworkPath!.trim().isNotEmpty;

  PlaybackTrack copyWith({
    String? songId,
    String? title,
    String? artistId,
    String? artistName,
    String? albumId,
    String? albumTitle,
    Object? albumEditionId = _unset,
    Object? albumEditionTitle = _unset,
    Object? artworkId = _unset,
    Object? artworkPath = _unset,
    String? filePath,
    Duration? duration,
    bool? isSongBlocked,
  }) {
    return PlaybackTrack(
      songId: songId ?? this.songId,
      title: title ?? this.title,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      albumId: albumId ?? this.albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumEditionId: identical(albumEditionId, _unset)
          ? this.albumEditionId
          : albumEditionId as String?,
      albumEditionTitle: identical(albumEditionTitle, _unset)
          ? this.albumEditionTitle
          : albumEditionTitle as String?,
      artworkId: identical(artworkId, _unset)
          ? this.artworkId
          : artworkId as String?,
      artworkPath: identical(artworkPath, _unset)
          ? this.artworkPath
          : artworkPath as String?,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      isSongBlocked: isSongBlocked ?? this.isSongBlocked,
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
