class LibraryArtist {
  const LibraryArtist({
    required this.artistId,
    required this.name,
    required this.albumCount,
    required this.songCount,
    required this.dateAdded,
    this.headerArtworkId,
    this.headerArtworkPath,
    this.topArtistsArtworkId,
    this.topArtistsArtworkPath,
  });

  final String artistId;
  final String name;

  final int albumCount;
  final int songCount;

  final String? headerArtworkId;
  final String? headerArtworkPath;

  final String? topArtistsArtworkId;
  final String? topArtistsArtworkPath;

  final DateTime dateAdded;
}
