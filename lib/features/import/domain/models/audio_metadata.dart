class AudioMetadata {
  const AudioMetadata({
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.durationSeconds,
    required this.trackNumber,
    required this.discNumber,
    required this.isSingle,
    required this.featuredArtists,
    this.releaseDate,
    this.genre,
  });

  final String title;
  final String artistName;
  final String albumTitle;
  final int durationSeconds;
  final int trackNumber;
  final int discNumber;
  final bool isSingle;
  final List<String> featuredArtists;
  final DateTime? releaseDate;
  final String? genre;

  AudioMetadata copyWith({
    String? title,
    String? artistName,
    String? albumTitle,
    int? durationSeconds,
    int? trackNumber,
    int? discNumber,
    bool? isSingle,
    List<String>? featuredArtists,
    DateTime? releaseDate,
    String? genre,
  }) {
    return AudioMetadata(
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      albumTitle: albumTitle ?? this.albumTitle,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      isSingle: isSingle ?? this.isSingle,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      releaseDate: releaseDate ?? this.releaseDate,
      genre: genre ?? this.genre,
    );
  }
}
