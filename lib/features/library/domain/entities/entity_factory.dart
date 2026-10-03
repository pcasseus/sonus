import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

abstract final class EntityFactory {
  static Artist createArtist({required String name, DateTime? now}) {
    final timestamp = now ?? DateTime.now();

    return Artist(
      id: EntityId.artist(),
      name: name.trim(),
      canonicalName: TextNormalizer.canonicalize(name),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static Album createAlbum({
    required String artistId,
    required String title,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return Album(
      id: EntityId.album(),
      artistId: artistId,
      title: title.trim(),
      canonicalTitle: TextNormalizer.canonicalize(title),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static AlbumEdition createAlbumEdition({
    required String albumId,
    required String title,
    AlbumEditionType type = AlbumEditionType.standard,
    bool isPrimary = false,
    DateTime? releaseDate,
    String? genre,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return AlbumEdition(
      id: EntityId.albumEdition(),
      albumId: albumId,
      title: title.trim(),
      type: type,
      isPrimary: isPrimary,
      releaseDate: releaseDate,
      genre: genre?.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static Song createSong({
    required String artistId,
    required String albumId,
    required String albumEditionId,
    required String title,
    required int trackNumber,
    int discNumber = 1,
    required int durationSeconds,
    bool isSingle = false,
    List<String> featuredArtists = const [],
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return Song(
      id: EntityId.song(),
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      title: title.trim(),
      canonicalTitle: TextNormalizer.canonicalize(title),
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationSeconds: durationSeconds,
      isSingle: isSingle,
      featuredArtists: List.unmodifiable(featuredArtists),
      versionLabel: versionLabel?.trim(),
      versionCharacteristics: List.unmodifiable(versionCharacteristics),
      releaseStatus: releaseStatus,
      isLeak: isLeak,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}
