class ListeningSessionStart {
  const ListeningSessionStart({
    required this.songId,
    required this.artistId,
    required this.albumId,
    required this.albumEditionId,
    required this.songTitle,
    required this.artistName,
    required this.albumTitle,
    required this.albumEditionTitle,
    required this.trackDuration,
    this.userId,
    this.sourceContext,
  });

  final String? userId;

  final String songId;
  final String artistId;
  final String albumId;
  final String albumEditionId;

  final String songTitle;
  final String artistName;
  final String albumTitle;
  final String albumEditionTitle;

  final Duration trackDuration;

  final String? sourceContext;
}
