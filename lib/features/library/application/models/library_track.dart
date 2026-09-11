import '../../domain/entities/album_edition.dart';

class LibraryTrack {
  const LibraryTrack({
    required this.songId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.albumEditionId,
    required this.albumEditionTitle,
    required this.albumEditionType,
    required this.trackNumber,
    required this.durationSeconds,
    required this.isSingle,
    required this.featuredArtists,
    required this.dateAdded,
    required this.isAvailable,
    this.filePath,
  });

  final String songId;
  final String title;

  final String artistId;
  final String artistName;

  final String albumId;
  final String albumTitle;

  final String albumEditionId;
  final String albumEditionTitle;
  final AlbumEditionType albumEditionType;

  final int trackNumber;
  final int durationSeconds;
  final bool isSingle;
  final List<String> featuredArtists;

  final DateTime dateAdded;

  final String? filePath;
  final bool isAvailable;
}
