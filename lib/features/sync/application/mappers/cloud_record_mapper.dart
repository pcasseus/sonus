import '../../../artwork/domain/entities/artwork_asset.dart';
import '../../../library/domain/entities/album.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../domain/models/cloud_records.dart';

abstract final class CloudRecordMapper {
  static CloudArtistRecord artist({
    required Artist artist,
    required String userId,
    List<MetadataFieldState> metadataFieldStates = const [],
  }) {
    return CloudArtistRecord(
      id: artist.id,
      userId: userId,
      name: artist.name,
      canonicalName: artist.canonicalName,
      headerArtworkId: artist.headerArtworkId,
      topArtistsArtworkId: artist.topArtistsArtworkId,
      metadataFieldStates: _metadataFieldStates(metadataFieldStates),
      createdAt: artist.createdAt,
      updatedAt: artist.updatedAt,
    );
  }

  static CloudAlbumRecord album({
    required Album album,
    required String userId,
    List<MetadataFieldState> metadataFieldStates = const [],
  }) {
    return CloudAlbumRecord(
      id: album.id,
      userId: userId,
      artistId: album.artistId,
      title: album.title,
      canonicalTitle: album.canonicalTitle,
      metadataFieldStates: _metadataFieldStates(metadataFieldStates),
      createdAt: album.createdAt,
      updatedAt: album.updatedAt,
    );
  }

  static CloudAlbumEditionRecord albumEdition({
    required AlbumEdition albumEdition,
    required String userId,
    List<MetadataFieldState> metadataFieldStates = const [],
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
      metadataFieldStates: _metadataFieldStates(metadataFieldStates),
      createdAt: albumEdition.createdAt,
      updatedAt: albumEdition.updatedAt,
    );
  }

  static CloudSongRecord song({
    required Song song,
    required String userId,
    List<MetadataFieldState> metadataFieldStates = const [],
  }) {
    return CloudSongRecord(
      id: song.id,
      userId: userId,
      artistId: song.artistId,
      albumId: song.albumId,
      albumEditionId: song.albumEditionId,
      title: song.title,
      canonicalTitle: song.canonicalTitle,
      trackNumber: song.trackNumber,
      discNumber: song.discNumber,
      durationSeconds: song.durationSeconds,
      isSingle: song.isSingle,
      isBlocked: song.isBlocked,
      featuredArtists: List<String>.unmodifiable(song.featuredArtists),
      versionLabel: song.versionLabel,
      versionCharacteristics: List<String>.unmodifiable(
        song.versionCharacteristics.map((value) => value.name),
      ),
      releaseStatus: song.releaseStatus.name,
      isLeak: song.isLeak,
      artworkId: song.artworkId,
      metadataFieldStates: _metadataFieldStates(metadataFieldStates),
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

  static List<CloudMetadataFieldState> _metadataFieldStates(
    List<MetadataFieldState> states,
  ) {
    return List<CloudMetadataFieldState>.unmodifiable(
      states.map(
        (state) => CloudMetadataFieldState(
          fieldName: state.fieldName,
          authority: state.authority.name,
          source: state.source.name,
          sourceReference: state.sourceReference,
          updatedAt: state.updatedAt.toUtc(),
        ),
      ),
    );
  }
}
