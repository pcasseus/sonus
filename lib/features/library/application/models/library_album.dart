import '../../domain/entities/album_edition.dart';

class LibraryAlbum {
  const LibraryAlbum({
    required this.albumId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.trackCount,
    required this.dateAdded,
    this.primaryEditionId,
    this.primaryEditionTitle,
    this.primaryEditionType,
    this.releaseDate,
    this.genre,
    this.artworkId,
    this.artworkPath,
  });

  final String albumId;
  final String title;

  final String artistId;
  final String artistName;

  final String? primaryEditionId;
  final String? primaryEditionTitle;
  final AlbumEditionType? primaryEditionType;

  final DateTime? releaseDate;
  final String? genre;

  final String? artworkId;
  final String? artworkPath;

  final int trackCount;
  final DateTime dateAdded;
}