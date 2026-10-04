import '../../domain/entities/album_edition.dart';

class LibraryAlbumEdition {
  const LibraryAlbumEdition({
    required this.editionId,
    required this.albumId,
    required this.title,
    required this.type,
    required this.isPrimary,
    required this.dateAdded,
    this.releaseDate,
    this.genre,
    this.artworkId,
    this.artworkPath,
  });

  final String editionId;
  final String albumId;
  final String title;
  final AlbumEditionType type;
  final bool isPrimary;

  final DateTime? releaseDate;
  final String? genre;

  final String? artworkId;
  final String? artworkPath;

  final DateTime dateAdded;
}
