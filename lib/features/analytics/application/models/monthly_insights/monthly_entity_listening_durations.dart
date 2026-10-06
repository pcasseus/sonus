class MonthlyEntityListeningDurations {
  const MonthlyEntityListeningDurations({
    required this.songs,
    required this.artists,
    required this.albums,
  });

  final Map<String, Duration> songs;
  final Map<String, Duration> artists;
  final Map<String, Duration> albums;

  Duration song(String songId) => songs[songId] ?? Duration.zero;

  Duration artist(String artistId) => artists[artistId] ?? Duration.zero;

  Duration album(String albumId) => albums[albumId] ?? Duration.zero;
}
