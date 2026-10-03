import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
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

  Future<LibraryIdentityMatch> resolve(
    AudioMetadata metadata, {
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
  }) async {
    final canonicalTrackArtist = TextNormalizer.canonicalize(
      metadata.artistName,
    );
    final canonicalAlbumArtist = TextNormalizer.canonicalize(
      metadata.effectiveAlbumArtistName,
    );
    final canonicalAlbum = TextNormalizer.canonicalize(metadata.albumTitle);
    final canonicalSong = TextNormalizer.canonicalize(metadata.title);

    final allArtists = await artistRepository.getAll();

    final trackArtistMatches = allArtists
        .where((artist) => artist.canonicalName == canonicalTrackArtist)
        .toList(growable: false);

    final albumArtistMatches = canonicalAlbumArtist == canonicalTrackArtist
        ? trackArtistMatches
        : allArtists
              .where((artist) => artist.canonicalName == canonicalAlbumArtist)
              .toList(growable: false);

    final trackArtistAmbiguous = trackArtistMatches.length > 1;
    final albumArtistAmbiguous = albumArtistMatches.length > 1;

    final trackArtist = trackArtistMatches.length == 1
        ? trackArtistMatches.single
        : null;

    final albumArtist = albumArtistMatches.length == 1
        ? albumArtistMatches.single
        : null;

    if (trackArtistAmbiguous || albumArtistAmbiguous) {
      return LibraryIdentityMatch(
        artist: trackArtist,
        albumArtist: albumArtist,
        album: null,
        edition: null,
        song: null,
        artistAmbiguous: trackArtistAmbiguous,
        albumArtistAmbiguous: albumArtistAmbiguous,
        albumAmbiguous: false,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    if (albumArtist == null) {
      return LibraryIdentityMatch(
        artist: trackArtist,
        albumArtist: null,
        album: null,
        edition: null,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: false,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    final artistAlbums = await albumRepository.getByArtistId(albumArtist.id);

    final albumMatches = artistAlbums
        .where((album) => album.canonicalTitle == canonicalAlbum)
        .toList(growable: false);

    if (albumMatches.length != 1) {
      return LibraryIdentityMatch(
        artist: trackArtist,
        albumArtist: albumArtist,
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
        artist: trackArtist,
        albumArtist: albumArtist,
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

    // A new track artist may legitimately be joining an existing soundtrack.
    // Without a resolved track artist, we cannot safely identify an existing
    // song merely by title.
    if (trackArtist == null) {
      return LibraryIdentityMatch(
        artist: null,
        albumArtist: albumArtist,
        album: album,
        edition: edition,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: false,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    final songs = await songRepository.getByEditionId(edition.id);

    final songMatches = songs
        .where(
          (song) =>
              song.artistId == trackArtist.id &&
              song.canonicalTitle == canonicalSong &&
              _sameVersionIdentity(
                song: song,
                versionLabel: versionLabel,
                versionCharacteristics: versionCharacteristics,
              ),
        )
        .toList(growable: false);

    return LibraryIdentityMatch(
      artist: trackArtist,
      albumArtist: albumArtist,
      album: album,
      edition: edition,
      song: songMatches.length == 1 ? songMatches.single : null,
      artistAmbiguous: false,
      albumAmbiguous: false,
      editionAmbiguous: false,
      songAmbiguous: songMatches.length > 1,
    );
  }

  bool _sameVersionIdentity({
    required Song song,
    required String? versionLabel,
    required List<SongVersionCharacteristic> versionCharacteristics,
  }) {
    final normalizedExpectedLabel = _normalizeVersionLabel(versionLabel);
    final normalizedSongLabel = _normalizeVersionLabel(song.versionLabel);

    if (normalizedSongLabel != normalizedExpectedLabel) {
      return false;
    }

    final songCharacteristics = song.versionCharacteristics.toSet();
    final expectedCharacteristics = versionCharacteristics.toSet();

    return songCharacteristics.length == expectedCharacteristics.length &&
        songCharacteristics.containsAll(expectedCharacteristics);
  }

  String? _normalizeVersionLabel(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return TextNormalizer.canonicalize(cleaned);
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
