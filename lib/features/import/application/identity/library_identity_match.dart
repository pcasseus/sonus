import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

class LibraryIdentityMatch {
  const LibraryIdentityMatch({
    this.artist,
    this.albumArtist,
    this.album,
    this.edition,
    this.song,
    required this.artistAmbiguous,
    this.albumArtistAmbiguous = false,
    required this.albumAmbiguous,
    required this.editionAmbiguous,
    required this.songAmbiguous,
  });

  /// Track artist.
  final Artist? artist;

  /// Artist that owns the album.
  final Artist? albumArtist;

  final Album? album;
  final AlbumEdition? edition;
  final Song? song;

  final bool artistAmbiguous;
  final bool albumArtistAmbiguous;
  final bool albumAmbiguous;
  final bool editionAmbiguous;
  final bool songAmbiguous;

  bool get hasAmbiguity =>
      artistAmbiguous ||
      albumArtistAmbiguous ||
      albumAmbiguous ||
      editionAmbiguous ||
      songAmbiguous;
}
