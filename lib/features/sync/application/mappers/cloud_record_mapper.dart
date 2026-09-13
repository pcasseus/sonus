import '../../../artwork/domain/entities/artwork_asset.dart';
import '../../../library/domain/entities/album.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../domain/models/cloud_records.dart';

abstract final class CloudRecordMapper {
  static CloudArtistRecord artist({
    required Artist artist,
    required String userId,
  }) {
    return CloudArtistRecord(
      id: artist.id,
      userId: userId,
      name: artist.name,
      canonicalName: artist.canonicalName,
      isBlacklisted: artist.isBlacklisted,
      headerArtworkId: artist.headerArtworkId,
      topArtistsArtworkId: artist.topArtistsArtworkId,
      createdAt: artist.createdAt,
      updatedAt: artist.updatedAt,
    );
  }

  static CloudAlbumRecord album({
    required Album album,
    required String userId,
  }) {
    return CloudAlbumRecord(
      id: album.id,
      userId: userId,
      artistId: album.artistId,
      title: album.title,
      canonicalTitle: album.canonicalTitle,
      createdAt: album.createdAt,
      updatedAt: album.updatedAt,
    );
  }

  static CloudAlbumEditionRecord albumEdition({
    required AlbumEdition albumEdition,
    required String userId,
  }) {
    return CloudAlbumEditionRecord(
      id: albumEdition.id,
      userId: userId,
      albumId: albumEdition.albumId,
      title: albumEdition.title,
      type: albumEdition.type.name,
      isPrimary: albumEdition.isPrimary,
      releaseDate: albumEdition.releaseDate,
      genre: albumEdition.genre,
      artworkId: albumEdition.artworkId,
      createdAt: albumEdition.createdAt,
      updatedAt: albumEdition.updatedAt,
    );
  }

  static CloudSongRecord song({required Song song, required String userId}) {
    return CloudSongRecord(
      id: song.id,
      userId: userId,
      artistId: song.artistId,
      albumId: song.albumId,
      albumEditionId: song.albumEditionId,
      title: song.title,
      canonicalTitle: song.canonicalTitle,
      trackNumber: song.trackNumber,
      durationSeconds: song.durationSeconds,
      isSingle: song.isSingle,
      featuredArtists: List<String>.unmodifiable(song.featuredArtists),
      artworkId: song.artworkId,
      createdAt: song.createdAt,
      updatedAt: song.updatedAt,
    );
  }

  static CloudArtworkAssetRecord artworkAsset({
    required ArtworkAsset artworkAsset,
    required String userId,
    required String storageObjectKey,
  }) {
    final trimmedStorageObjectKey = storageObjectKey.trim();

    if (trimmedStorageObjectKey.isEmpty) {
      throw ArgumentError.value(
        storageObjectKey,
        'storageObjectKey',
        'Cloud artwork storage object key cannot be empty.',
      );
    }

    return CloudArtworkAssetRecord(
      id: artworkAsset.id,
      userId: userId,
      storageObjectKey: trimmedStorageObjectKey,
      createdAt: artworkAsset.createdAt,
      updatedAt: artworkAsset.updatedAt,
    );
  }
}
