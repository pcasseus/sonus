import '../../../../core/identity/text_normalizer.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../domain/entities/artwork_asset.dart';
import '../../domain/entities/artwork_asset_factory.dart';
import '../../domain/repositories/artwork_asset_repository.dart';

class ArtworkAssignmentService {
  const ArtworkAssignmentService({
    required this.artworkAssetRepository,
    required this.artistRepository,
    required this.albumEditionRepository,
    required this.songRepository,
  });

  final ArtworkAssetRepository artworkAssetRepository;
  final ArtistRepository artistRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;

  Future<ArtworkAsset> resolveArtworkAsset({
    required String filePath,
    DateTime? now,
  }) async {
    final trimmedPath = filePath.trim();

    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Artwork file path cannot be empty.',
      );
    }

    final normalizedPath = TextNormalizer.normalizePath(trimmedPath);

    final existing = await artworkAssetRepository.getByNormalizedPath(
      normalizedPath,
    );

    if (existing != null) {
      return existing;
    }

    final artworkAsset = ArtworkAssetFactory.create(
      filePath: trimmedPath,
      now: now,
    );

    await artworkAssetRepository.create(artworkAsset);

    return artworkAsset;
  }

  Future<ArtworkAsset> assignArtistHeader({
    required String artistId,
    required String filePath,
    DateTime? now,
  }) async {
    final artist = await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();

    final artwork = await resolveArtworkAsset(
      filePath: filePath,
      now: timestamp,
    );

    await artistRepository.save(
      artist.copyWith(headerArtworkId: artwork.id, updatedAt: timestamp),
    );

    return artwork;
  }

  Future<ArtworkAsset> assignArtistTopArtists({
    required String artistId,
    required String filePath,
    DateTime? now,
  }) async {
    final artist = await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();

    final artwork = await resolveArtworkAsset(
      filePath: filePath,
      now: timestamp,
    );

    await artistRepository.save(
      artist.copyWith(topArtistsArtworkId: artwork.id, updatedAt: timestamp),
    );

    return artwork;
  }

  Future<ArtworkAsset> assignAlbumEdition({
    required String albumEditionId,
    required String filePath,
    DateTime? now,
  }) async {
    final edition = await _requireAlbumEdition(albumEditionId);
    final timestamp = now ?? DateTime.now();

    final artwork = await resolveArtworkAsset(
      filePath: filePath,
      now: timestamp,
    );

    await albumEditionRepository.save(
      edition.copyWith(artworkId: artwork.id, updatedAt: timestamp),
    );

    return artwork;
  }

  Future<ArtworkAsset> assignSong({
    required String songId,
    required String filePath,
    DateTime? now,
  }) async {
    final song = await _requireSong(songId);
    final timestamp = now ?? DateTime.now();

    final artwork = await resolveArtworkAsset(
      filePath: filePath,
      now: timestamp,
    );

    await songRepository.save(
      song.copyWith(artworkId: artwork.id, updatedAt: timestamp),
    );

    return artwork;
  }

  Future<void> clearArtistHeader(String artistId, {DateTime? now}) async {
    final artist = await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();

    await artistRepository.save(
      artist.copyWith(headerArtworkId: null, updatedAt: timestamp),
    );
  }

  Future<void> clearArtistTopArtists(String artistId, {DateTime? now}) async {
    final artist = await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();

    await artistRepository.save(
      artist.copyWith(topArtistsArtworkId: null, updatedAt: timestamp),
    );
  }

  Future<void> clearAlbumEdition(String albumEditionId, {DateTime? now}) async {
    final edition = await _requireAlbumEdition(albumEditionId);
    final timestamp = now ?? DateTime.now();

    await albumEditionRepository.save(
      edition.copyWith(artworkId: null, updatedAt: timestamp),
    );
  }

  Future<void> clearSong(String songId, {DateTime? now}) async {
    final song = await _requireSong(songId);
    final timestamp = now ?? DateTime.now();

    await songRepository.save(
      song.copyWith(artworkId: null, updatedAt: timestamp),
    );
  }

  Future<Artist> _requireArtist(String artistId) async {
    final artist = await artistRepository.getById(artistId);

    if (artist == null) {
      throw StateError('Artist not found: $artistId');
    }

    return artist;
  }

  Future<AlbumEdition> _requireAlbumEdition(String albumEditionId) async {
    final edition = await albumEditionRepository.getById(albumEditionId);

    if (edition == null) {
      throw StateError('Album edition not found: $albumEditionId');
    }

    return edition;
  }

  Future<Song> _requireSong(String songId) async {
    final song = await songRepository.getById(songId);

    if (song == null) {
      throw StateError('Song not found: $songId');
    }

    return song;
  }
}
