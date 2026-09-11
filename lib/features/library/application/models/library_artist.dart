class LibraryArtist {
  const LibraryArtist({
    required this.artistId,
    required this.name,
    required this.albumCount,
    required this.songCount,
    required this.dateAdded,
  });

  final String artistId;
  final String name;

  final int albumCount;
  final int songCount;

  final DateTime dateAdded;
}
