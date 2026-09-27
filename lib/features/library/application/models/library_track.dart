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
    this.discNumber = 1,
    required this.durationSeconds,
    required this.isSingle,
    required this.featuredArtists,
    required this.dateAdded,
    required this.isAvailable,
    this.isSongBlocked = false,
    this.isArtistBlacklisted = false,
    this.filePath,
    this.artworkId,
    this.artworkPath,
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
  final int discNumber;
  final int durationSeconds;
  final bool isSingle;
  final List<String> featuredArtists;

  final DateTime dateAdded;

  final String? filePath;
  final bool isAvailable;

  final bool isSongBlocked;
  final bool isArtistBlacklisted;

  bool get isBlocked => isSongBlocked || isArtistBlacklisted;

  final String? artworkId;
  final String? artworkPath;
}
