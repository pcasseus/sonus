import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';

import 'library_identity_match.dart';

class LibraryIdentityResolver {
  const LibraryIdentityResolver({
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.songRepository,
  });

  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;

  Future<LibraryIdentityMatch> resolve(AudioMetadata metadata) async {
    final canonicalArtist = TextNormalizer.canonicalize(metadata.artistName);
    final canonicalAlbum = TextNormalizer.canonicalize(metadata.albumTitle);
    final canonicalSong = TextNormalizer.canonicalize(metadata.title);

    final allArtists = await artistRepository.getAll();

    final artistMatches = allArtists
        .where((artist) => artist.canonicalName == canonicalArtist)
        .toList(growable: false);

    if (artistMatches.length != 1) {
      return LibraryIdentityMatch(
        artist: null,
        album: null,
        edition: null,
        song: null,
        artistAmbiguous: artistMatches.length > 1,
        albumAmbiguous: false,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    final artist = artistMatches.single;
    final artistAlbums = await albumRepository.getByArtistId(artist.id);

    final albumMatches = artistAlbums
        .where((album) => album.canonicalTitle == canonicalAlbum)
        .toList(growable: false);

    if (albumMatches.length != 1) {
      return LibraryIdentityMatch(
        artist: artist,
        album: null,
        edition: null,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: albumMatches.length > 1,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    final album = albumMatches.single;
    final editions = await albumEditionRepository.getByAlbumId(album.id);

    final editionResolution = _resolveEdition(
      editions,
      albumTitle: canonicalAlbum,
    );

    if (editionResolution.edition == null) {
      return LibraryIdentityMatch(
        artist: artist,
        album: album,
        edition: null,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: false,
        editionAmbiguous: editionResolution.ambiguous,
        songAmbiguous: false,
      );
    }

    final edition = editionResolution.edition!;
    final songs = await songRepository.getByEditionId(edition.id);

    final songMatches = songs
        .where((song) => song.canonicalTitle == canonicalSong)
        .toList(growable: false);

    return LibraryIdentityMatch(
      artist: artist,
      album: album,
      edition: edition,
      song: songMatches.length == 1 ? songMatches.single : null,
      artistAmbiguous: false,
      albumAmbiguous: false,
      editionAmbiguous: false,
      songAmbiguous: songMatches.length > 1,
    );
  }

  _EditionResolution _resolveEdition(
    List<AlbumEdition> editions, {
    required String albumTitle,
  }) {
    if (editions.isEmpty) {
      return const _EditionResolution();
    }

    final primaryEditions = editions
        .where((edition) => edition.isPrimary)
        .toList(growable: false);

    if (primaryEditions.length == 1) {
      return _EditionResolution(edition: primaryEditions.single);
    }

    if (primaryEditions.length > 1) {
      return const _EditionResolution(ambiguous: true);
    }

    final titleMatches = editions
        .where(
          (edition) => TextNormalizer.canonicalize(edition.title) == albumTitle,
        )
        .toList(growable: false);

    if (titleMatches.length == 1) {
      return _EditionResolution(edition: titleMatches.single);
    }

    if (titleMatches.length > 1) {
      return const _EditionResolution(ambiguous: true);
    }

    if (editions.length == 1) {
      return _EditionResolution(edition: editions.single);
    }

    return const _EditionResolution(ambiguous: true);
  }
}

class _EditionResolution {
  const _EditionResolution({this.edition, this.ambiguous = false});

  final AlbumEdition? edition;
  final bool ambiguous;
}
