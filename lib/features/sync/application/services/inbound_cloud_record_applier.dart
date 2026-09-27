import '../../../library/domain/entities/album.dart';
import '../../../library/domain/entities/album_edition.dart';
import '../../../library/domain/entities/artist.dart';
import '../../../library/domain/entities/song.dart';
import '../../domain/models/cloud_records.dart';
import 'sync_mutation_context.dart';

class InboundCloudRecordApplier {
  const InboundCloudRecordApplier();

  Future<void> apply({
    required CloudOwnedRecord record,
    required SyncMutationContext context,
  }) async {
    if (record.isDeleted) {
      throw StateError(
        'Inbound tombstone reconciliation is not implemented yet.',
      );
    }

    switch (record) {
      case CloudArtistRecord():
        await _applyArtist(record, context);

      case CloudAlbumRecord():
        await _applyAlbum(record, context);

      case CloudAlbumEditionRecord():
        await _applyAlbumEdition(record, context);

      case CloudSongRecord():
        await _applySong(record, context);

      case CloudArtworkAssetRecord():
        throw StateError(
          'Inbound artwork requires Storage download before reconciliation.',
        );

      default:
        throw ArgumentError.value(
          record,
          'record',
          'Unsupported cloud record type.',
        );
    }
  }

  Future<void> _applyArtist(
    CloudArtistRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Artist(
      id: record.id,
      name: record.name,
      canonicalName: record.canonicalName,
      isBlacklisted: record.isBlacklisted,
      headerArtworkId: record.headerArtworkId,
      topArtistsArtworkId: record.topArtistsArtworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.artistRepository.getById(record.id);

    if (existing == null) {
      await context.artistRepository.create(entity);
      return;
    }

    await context.artistRepository.save(entity);
  }

  Future<void> _applyAlbum(
    CloudAlbumRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Album(
      id: record.id,
      artistId: record.artistId,
      title: record.title,
      canonicalTitle: record.canonicalTitle,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.albumRepository.getById(record.id);

    if (existing == null) {
      await context.albumRepository.create(entity);
      return;
    }

    await context.albumRepository.save(entity);
  }

  Future<void> _applyAlbumEdition(
    CloudAlbumEditionRecord record,
    SyncMutationContext context,
  ) async {
    final entity = AlbumEdition(
      id: record.id,
      albumId: record.albumId,
      title: record.title,
      type: _albumEditionType(record.type),
      isPrimary: record.isPrimary,
      releaseDate: record.releaseDate,
      genre: record.genre,
      artworkId: record.artworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.albumEditionRepository.getById(record.id);

    if (existing == null) {
      await context.albumEditionRepository.create(entity);
      return;
    }

    await context.albumEditionRepository.save(entity);
  }

  Future<void> _applySong(
    CloudSongRecord record,
    SyncMutationContext context,
  ) async {
    final entity = Song(
      id: record.id,
      artistId: record.artistId,
      albumId: record.albumId,
      albumEditionId: record.albumEditionId,
      title: record.title,
      canonicalTitle: record.canonicalTitle,
      trackNumber: record.trackNumber,
      discNumber: record.discNumber,
      durationSeconds: record.durationSeconds,
      isSingle: record.isSingle,
      isBlocked: record.isBlocked,
      featuredArtists: record.featuredArtists,
      artworkId: record.artworkId,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );

    final existing = await context.songRepository.getById(record.id);

    if (existing == null) {
      await context.songRepository.create(entity);
      return;
    }

    await context.songRepository.save(entity);
  }

  AlbumEditionType _albumEditionType(String value) {
    return switch (value) {
      'standard' => AlbumEditionType.standard,
      'deluxe' => AlbumEditionType.deluxe,
      'expanded' => AlbumEditionType.expanded,
      'anniversary' => AlbumEditionType.anniversary,
      'remaster' => AlbumEditionType.remaster,
      'other' => AlbumEditionType.other,
      _ => throw StateError('Unsupported album edition type: $value'),
    };
  }
}
