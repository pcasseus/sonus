import '../../../../core/identity/text_normalizer.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/metadata/metadata_fields.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../../library/domain/services/metadata_field_state_service.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../domain/entities/artwork_asset.dart';
import '../../domain/entities/artwork_asset_factory.dart';
import '../../domain/repositories/artwork_asset_repository.dart';
import 'artwork_managed_storage.dart';

class ArtworkAssignmentService {
  const ArtworkAssignmentService({
    required this.artworkAssetRepository,
    required this.artistRepository,
    required this.albumEditionRepository,
    required this.songRepository,
    this.artworkManagedStorage,
    this.mutationRunner,
  });

  final ArtworkAssetRepository artworkAssetRepository;
  final ArtistRepository artistRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;
  final ArtworkManagedStorage? artworkManagedStorage;
  final SyncMutationRunner? mutationRunner;

  Future<ArtworkAsset> resolveArtworkAsset({
    required String filePath,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final resolvedPath = await _resolveArtworkPath(filePath);

    return _resolveArtworkAssetForPath(
      repository: artworkAssetRepository,
      resolvedPath: resolvedPath,
      now: timestamp,
    );
  }

  Future<ArtworkAsset> assignArtistHeader({
    String? userId,
    required String artistId,
    required String filePath,
    DateTime? now,
  }) async {
    await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();
    final resolvedPath = await _resolveArtworkPath(filePath);
    final runner = mutationRunner;

    if (runner == null) {
      final artwork = await _resolveArtworkAssetForPath(
        repository: artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      final artist = await _requireArtist(artistId);

      if (artist.headerArtworkId != artwork.id) {
        await artistRepository.save(
          artist.copyWith(headerArtworkId: artwork.id, updatedAt: timestamp),
        );
      }

      return artwork;
    }

    return runner.run((context) async {
      final artist = await context.artistRepository.getById(artistId);

      if (artist == null) {
        throw StateError('Artist not found: $artistId');
      }

      final artwork = await _resolveArtworkAssetForPath(
        repository: context.artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (artist.headerArtworkId == artwork.id) {
        return artwork;
      }

      await context.artistRepository.save(
        artist.copyWith(headerArtworkId: artwork.id, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Artist metadata repository is unavailable.');
      }

      await MetadataFieldStateService(repository: metadataRepository).record(
        entityType: MetadataEntityType.artist,
        entityId: artistId,
        fieldName: MetadataFields.artistHeaderArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: timestamp,
      );

      await context.localSyncRepository.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
      );

      return artwork;
    });
  }

  Future<ArtworkAsset> assignArtistTopArtists({
    String? userId,
    required String artistId,
    required String filePath,
    DateTime? now,
  }) async {
    await _requireArtist(artistId);
    final timestamp = now ?? DateTime.now();
    final resolvedPath = await _resolveArtworkPath(filePath);
    final runner = mutationRunner;

    if (runner == null) {
      final artwork = await _resolveArtworkAssetForPath(
        repository: artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      final artist = await _requireArtist(artistId);

      if (artist.topArtistsArtworkId != artwork.id) {
        await artistRepository.save(
          artist.copyWith(
            topArtistsArtworkId: artwork.id,
            updatedAt: timestamp,
          ),
        );
      }

      return artwork;
    }

    return runner.run((context) async {
      final artist = await context.artistRepository.getById(artistId);

      if (artist == null) {
        throw StateError('Artist not found: $artistId');
      }

      final artwork = await _resolveArtworkAssetForPath(
        repository: context.artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (artist.topArtistsArtworkId == artwork.id) {
        return artwork;
      }

      await context.artistRepository.save(
        artist.copyWith(topArtistsArtworkId: artwork.id, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Artist metadata repository is unavailable.');
      }

      await MetadataFieldStateService(repository: metadataRepository).record(
        entityType: MetadataEntityType.artist,
        entityId: artistId,
        fieldName: MetadataFields.artistTopArtistsArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: timestamp,
      );

      await context.localSyncRepository.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
      );

      return artwork;
    });
  }

  Future<ArtworkAsset> assignAlbumEdition({
    required String albumEditionId,
    required String filePath,
    DateTime? now,
  }) async {
    // Preserve the existing contract: missing entities fail before artwork
    // storage or artwork-asset creation occurs.
    await _requireAlbumEdition(albumEditionId);

    final timestamp = now ?? DateTime.now();
    final resolvedPath = await _resolveArtworkPath(filePath);
    final runner = mutationRunner;

    if (runner == null) {
      final edition = await _requireAlbumEdition(albumEditionId);

      final artwork = await _resolveArtworkAssetForPath(
        repository: artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (edition.artworkId == artwork.id) {
        return artwork;
      }

      await albumEditionRepository.save(
        edition.copyWith(artworkId: artwork.id, updatedAt: timestamp),
      );

      return artwork;
    }

    return runner.run((context) async {
      final edition = await context.albumEditionRepository.getById(
        albumEditionId,
      );

      if (edition == null) {
        throw StateError('Album edition not found: $albumEditionId');
      }

      final artwork = await _resolveArtworkAssetForPath(
        repository: context.artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (edition.artworkId == artwork.id) {
        return artwork;
      }

      await context.albumEditionRepository.save(
        edition.copyWith(artworkId: artwork.id, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.albumEdition,
          entityId: edition.id,
          fieldName: MetadataFields.editionArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }

      return artwork;
    });
  }

  Future<ArtworkAsset> assignSong({
    required String songId,
    required String filePath,
    DateTime? now,
  }) async {
    // Preserve the existing contract: missing entities fail before artwork
    // storage or artwork-asset creation occurs.
    await _requireSong(songId);

    final timestamp = now ?? DateTime.now();
    final resolvedPath = await _resolveArtworkPath(filePath);
    final runner = mutationRunner;

    if (runner == null) {
      final song = await _requireSong(songId);

      final artwork = await _resolveArtworkAssetForPath(
        repository: artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (song.artworkId == artwork.id) {
        return artwork;
      }

      await songRepository.save(
        song.copyWith(artworkId: artwork.id, updatedAt: timestamp),
      );

      return artwork;
    }

    return runner.run((context) async {
      final song = await context.songRepository.getById(songId);

      if (song == null) {
        throw StateError('Song not found: $songId');
      }

      final artwork = await _resolveArtworkAssetForPath(
        repository: context.artworkAssetRepository,
        resolvedPath: resolvedPath,
        now: timestamp,
      );

      if (song.artworkId == artwork.id) {
        return artwork;
      }

      await context.songRepository.save(
        song.copyWith(artworkId: artwork.id, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }

      return artwork;
    });
  }

  Future<void> clearArtistHeader(
    String artistId, {
    String? userId,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final runner = mutationRunner;

    if (runner == null) {
      final artist = await _requireArtist(artistId);

      if (artist.headerArtworkId == null) {
        return;
      }

      await artistRepository.save(
        artist.copyWith(headerArtworkId: null, updatedAt: timestamp),
      );

      return;
    }

    await runner.run((context) async {
      final artist = await context.artistRepository.getById(artistId);

      if (artist == null) {
        throw StateError('Artist not found: $artistId');
      }

      if (artist.headerArtworkId == null) {
        return;
      }

      await context.artistRepository.save(
        artist.copyWith(headerArtworkId: null, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Artist metadata repository is unavailable.');
      }

      await MetadataFieldStateService(repository: metadataRepository).record(
        entityType: MetadataEntityType.artist,
        entityId: artistId,
        fieldName: MetadataFields.artistHeaderArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: timestamp,
      );

      await context.localSyncRepository.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
      );
    });
  }

  Future<void> clearArtistTopArtists(
    String artistId, {
    String? userId,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final runner = mutationRunner;

    if (runner == null) {
      final artist = await _requireArtist(artistId);

      if (artist.topArtistsArtworkId == null) {
        return;
      }

      await artistRepository.save(
        artist.copyWith(topArtistsArtworkId: null, updatedAt: timestamp),
      );

      return;
    }

    await runner.run((context) async {
      final artist = await context.artistRepository.getById(artistId);

      if (artist == null) {
        throw StateError('Artist not found: $artistId');
      }

      if (artist.topArtistsArtworkId == null) {
        return;
      }

      await context.artistRepository.save(
        artist.copyWith(topArtistsArtworkId: null, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository == null) {
        throw StateError('Artist metadata repository is unavailable.');
      }

      await MetadataFieldStateService(repository: metadataRepository).record(
        entityType: MetadataEntityType.artist,
        entityId: artistId,
        fieldName: MetadataFields.artistTopArtistsArtwork,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: timestamp,
      );

      await context.localSyncRepository.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
      );
    });
  }

  Future<void> clearAlbumEdition(String albumEditionId, {DateTime? now}) async {
    final runner = mutationRunner;

    if (runner == null) {
      final edition = await _requireAlbumEdition(albumEditionId);

      if (edition.artworkId == null) {
        return;
      }

      final timestamp = now ?? DateTime.now();

      await albumEditionRepository.save(
        edition.copyWith(artworkId: null, updatedAt: timestamp),
      );

      return;
    }

    final timestamp = now ?? DateTime.now();

    await runner.run((context) async {
      final edition = await context.albumEditionRepository.getById(
        albumEditionId,
      );

      if (edition == null) {
        throw StateError('Album edition not found: $albumEditionId');
      }

      if (edition.artworkId == null) {
        return;
      }

      await context.albumEditionRepository.save(
        edition.copyWith(artworkId: null, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.albumEdition,
          entityId: edition.id,
          fieldName: MetadataFields.editionArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }
    });
  }

  Future<void> clearSong(String songId, {DateTime? now}) async {
    final runner = mutationRunner;

    if (runner == null) {
      final song = await _requireSong(songId);

      if (song.artworkId == null) {
        return;
      }

      final timestamp = now ?? DateTime.now();

      await songRepository.save(
        song.copyWith(artworkId: null, updatedAt: timestamp),
      );

      return;
    }

    final timestamp = now ?? DateTime.now();

    await runner.run((context) async {
      final song = await context.songRepository.getById(songId);

      if (song == null) {
        throw StateError('Song not found: $songId');
      }

      if (song.artworkId == null) {
        return;
      }

      await context.songRepository.save(
        song.copyWith(artworkId: null, updatedAt: timestamp),
      );

      final metadataRepository = context.metadataFieldStateRepository;

      if (metadataRepository != null) {
        await MetadataFieldStateService(repository: metadataRepository).record(
          entityType: MetadataEntityType.song,
          entityId: song.id,
          fieldName: MetadataFields.songArtwork,
          authority: MetadataAuthority.manual,
          source: MetadataProvenanceSource.user,
          updatedAt: timestamp,
        );
      }
    });
  }

  Future<String> _resolveArtworkPath(String filePath) async {
    final trimmedPath = filePath.trim();

    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Artwork file path cannot be empty.',
      );
    }

    final storage = artworkManagedStorage;

    if (storage == null) {
      return trimmedPath;
    }

    return storage.importArtwork(trimmedPath);
  }

  Future<ArtworkAsset> _resolveArtworkAssetForPath({
    required ArtworkAssetRepository repository,
    required String resolvedPath,
    required DateTime now,
  }) async {
    final normalizedPath = TextNormalizer.normalizePath(resolvedPath);

    final existing = await repository.getByNormalizedPath(normalizedPath);

    if (existing != null) {
      return existing;
    }

    final artworkAsset = ArtworkAssetFactory.create(
      filePath: resolvedPath,
      now: now,
    );

    await repository.create(artworkAsset);

    return artworkAsset;
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
