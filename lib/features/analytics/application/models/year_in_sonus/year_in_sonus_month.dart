class YearInSonusMonth {
  const YearInSonusMonth({
    required this.month,
    required this.streams,
    required this.topSongId,
    required this.topArtistId,
    this.listeningDuration = Duration.zero,
  });

  final DateTime month;

  final int streams;
  final Duration listeningDuration;

  final String? topSongId;
  final String? topArtistId;

  bool get hasListening => streams > 0 || listeningDuration > Duration.zero;
}
