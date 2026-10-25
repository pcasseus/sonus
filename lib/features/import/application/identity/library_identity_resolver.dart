import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/services/edition_title_parser.dart';

import 'library_identity_match.dart';
import 'recording_evidence.dart';

/// Which album a file joins (SN-45 folder rule).
sealed class AlbumPlacement {
  const AlbumPlacement();

  /// By album artist and title tags, as before SN-45.
  static const AlbumPlacement automatic = _AutomaticPlacement();

  /// A new album, even if an album with the same title and artist exists:
  /// the file's folder is a different project.
  static const AlbumPlacement separate = _SeparatePlacement();
}

class _AutomaticPlacement extends AlbumPlacement {
  const _AutomaticPlacement();
}

class _SeparatePlacement extends AlbumPlacement {
  const _SeparatePlacement();
}

/// The album the file's folder already belongs to; [edition] when the
/// folder's songs are on one edition of it.
class WithinAlbumPlacement extends AlbumPlacement {
  const WithinAlbumPlacement(this.album, {this.edition});

  final Album album;
  final AlbumEdition? edition;
}

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
    AlbumPlacement placement = AlbumPlacement.automatic,
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

    // SN-45: a file joining its folder's album needs only its performer; the
    // album, its owner and edition are already known.
    if (placement is WithinAlbumPlacement) {
      return _resolveWithin(
        placement,
        metadata: metadata,
        trackArtist: trackArtistMatches.length == 1
            ? trackArtistMatches.single
            : null,
        trackArtistAmbiguous: trackArtistAmbiguous,
        canonicalSong: canonicalSong,
        versionLabel: versionLabel,
        versionCharacteristics: versionCharacteristics,
      );
    }

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

    if (placement is _SeparatePlacement) {
      return LibraryIdentityMatch(
        artist: trackArtist,
        albumArtist: albumArtist,
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

    var albumMatches = artistAlbums
        .where((album) => album.canonicalTitle == canonicalAlbum)
        .toList(growable: false);

    // "locket (Deluxe)" with no album of that exact name belongs to "locket"
    // as a Deluxe edition. Only recognized edition phrases count.
    final qualified = EditionTitleParser.parse(metadata.albumTitle);

    if (albumMatches.isEmpty && qualified != null) {
      final canonicalBase = TextNormalizer.canonicalize(qualified.baseTitle);
      albumMatches = artistAlbums
          .where((album) => album.canonicalTitle == canonicalBase)
          .toList(growable: false);
    }

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
      fileAlbumTitle: canonicalAlbum,
      qualified: qualified,
    );

    if (editionResolution.ambiguous) {
      return LibraryIdentityMatch(
        artist: trackArtist,
        albumArtist: albumArtist,
        album: album,
        edition: null,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: false,
        editionAmbiguous: true,
        songAmbiguous: false,
      );
    }

    final edition = editionResolution.edition;

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
        newEditionType: editionResolution.newEditionType,
      );
    }

    // The same recording may already be on another edition of this album
    // (a Standard track on the Deluxe), so the whole album is searched.
    final songs = await songRepository.getByAlbumId(album.id);

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

    // Several recordings can share artist, title and album (an album and a
    // radio edit, a solo and a featured version). Only songs the evidence
    // doesn't set apart are the same recording.
    final sameRecording = songMatches
        .where((song) => !RecordingEvidence.distinguishes(song, metadata))
        .toList(growable: false);

    return LibraryIdentityMatch(
      artist: trackArtist,
      albumArtist: albumArtist,
      album: album,
      edition: edition,
      song: sameRecording.length == 1 ? sameRecording.single : null,
      artistAmbiguous: false,
      albumAmbiguous: false,
      editionAmbiguous: false,
      songAmbiguous: sameRecording.length > 1,
      alternateRecordingOf: sameRecording.isEmpty && songMatches.isNotEmpty
          ? songMatches.first
          : null,
      newEditionType: editionResolution.newEditionType,
    );
  }

  Future<LibraryIdentityMatch> _resolveWithin(
    WithinAlbumPlacement placement, {
    required AudioMetadata metadata,
    required Artist? trackArtist,
    required bool trackArtistAmbiguous,
    required String canonicalSong,
    required String? versionLabel,
    required List<SongVersionCharacteristic> versionCharacteristics,
  }) async {
    final album = placement.album;
    final owner = await artistRepository.getById(album.artistId);

    if (trackArtistAmbiguous || owner == null) {
      return LibraryIdentityMatch(
        artist: null,
        albumArtist: owner,
        album: album,
        edition: null,
        song: null,
        artistAmbiguous: trackArtistAmbiguous,
        albumAmbiguous: owner == null,
        editionAmbiguous: false,
        songAmbiguous: false,
      );
    }

    var edition = placement.edition;
    AlbumEditionType? newEditionType;

    if (edition == null) {
      final editions = await albumEditionRepository.getByAlbumId(album.id);
      final resolution = _resolveEdition(
        editions,
        fileAlbumTitle: TextNormalizer.canonicalize(metadata.albumTitle),
        qualified: EditionTitleParser.parse(metadata.albumTitle),
      );
      edition = resolution.ambiguous
          ? editions.where((e) => e.isPrimary).firstOrNull
          : resolution.edition;
      newEditionType = edition == null ? resolution.newEditionType : null;
    }

    if (trackArtist == null) {
      return LibraryIdentityMatch(
        artist: null,
        albumArtist: owner,
        album: album,
        edition: edition,
        song: null,
        artistAmbiguous: false,
        albumAmbiguous: false,
        editionAmbiguous: false,
        songAmbiguous: false,
        newEditionType: newEditionType,
      );
    }

    final songs = await songRepository.getByAlbumId(album.id);
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
    final sameRecording = songMatches
        .where((song) => !RecordingEvidence.distinguishes(song, metadata))
        .toList(growable: false);

    return LibraryIdentityMatch(
      artist: trackArtist,
      albumArtist: owner,
      album: album,
      edition: edition,
      song: sameRecording.length == 1 ? sameRecording.single : null,
      artistAmbiguous: false,
      albumAmbiguous: false,
      editionAmbiguous: false,
      songAmbiguous: sameRecording.length > 1,
      alternateRecordingOf: sameRecording.isEmpty && songMatches.isNotEmpty
          ? songMatches.first
          : null,
      newEditionType: newEditionType,
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
    required String fileAlbumTitle,
    required ParsedEditionTitle? qualified,
  }) {
    // The edition named exactly like the file's album, e.g. "locket (Deluxe)".
    final titleMatches = editions
        .where(
          (edition) =>
              TextNormalizer.canonicalize(edition.title) == fileAlbumTitle,
        )
        .toList(growable: false);

    if (titleMatches.length == 1) {
      return _EditionResolution(edition: titleMatches.single);
    }

    if (titleMatches.length > 1) {
      return const _EditionResolution(ambiguous: true);
    }

    // A recognized edition the album doesn't have yet.
    if (qualified != null) {
      return _EditionResolution(newEditionType: qualified.type);
    }

    if (editions.isEmpty) {
      return const _EditionResolution();
    }

    // An unqualified file for an album that so far only has recognized
    // special editions (the Deluxe was imported first) is the Standard.
    // Editions that aren't recognizably special keep the rules below.
    if (editions.every(
      (edition) =>
          edition.type != AlbumEditionType.standard &&
          EditionTitleParser.parse(edition.title) != null,
    )) {
      return const _EditionResolution(
        newEditionType: AlbumEditionType.standard,
      );
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

    if (editions.length == 1) {
      return _EditionResolution(edition: editions.single);
    }

    return const _EditionResolution(ambiguous: true);
  }
}

class _EditionResolution {
  const _EditionResolution({
    this.edition,
    this.ambiguous = false,
    this.newEditionType,
  });

  final AlbumEdition? edition;
  final bool ambiguous;
  final AlbumEditionType? newEditionType;
}
