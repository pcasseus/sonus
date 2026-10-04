import 'dart:convert';

import '../../domain/entities/song.dart';

abstract final class SongRowMapper {
  static Map<String, Object?> toRow(Song song) {
    return {
      'id': song.id,
      'artist_id': song.artistId,
      'album_id': song.albumId,
      'album_edition_id': song.albumEditionId,
      'title': song.title,
      'canonical_title': song.canonicalTitle,
      'track_number': song.trackNumber,
      'disc_number': song.discNumber,
      'duration_seconds': song.durationSeconds,
      'is_single': song.isSingle ? 1 : 0,
      'is_blocked': song.isBlocked ? 1 : 0,
      'artwork_id': song.artworkId,
      'featured_artists': jsonEncode(song.featuredArtists),
      'version_label': song.versionLabel,
      'version_characteristics': jsonEncode(
        song.versionCharacteristics
            .map((characteristic) => characteristic.name)
            .toList(growable: false),
      ),
      'release_status': song.releaseStatus.name,
      'is_leak': song.isLeak ? 1 : 0,
      'created_at': song.createdAt.toUtc().toIso8601String(),
      'updated_at': song.updatedAt.toUtc().toIso8601String(),
    };
  }

  static Song fromRow(Map<String, Object?> row) {
    final decodedFeaturedArtists = jsonDecode(
      row['featured_artists'] as String? ?? '[]',
    );

    final decodedVersionCharacteristics = jsonDecode(
      row['version_characteristics'] as String? ?? '[]',
    );
    return Song(
      id: row['id'] as String,
      artistId: row['artist_id'] as String,
      albumId: row['album_id'] as String,
      albumEditionId: row['album_edition_id'] as String,
      title: row['title'] as String,
      canonicalTitle: row['canonical_title'] as String,
      trackNumber: row['track_number'] as int? ?? 0,
      discNumber: row['disc_number'] as int? ?? 1,
      durationSeconds: row['duration_seconds'] as int? ?? 0,
      isSingle: (row['is_single'] as int? ?? 0) == 1,
      isBlocked: (row['is_blocked'] as int? ?? 0) == 1,
      artworkId: row['artwork_id'] as String?,
      featuredArtists: List<String>.unmodifiable(
        (decodedFeaturedArtists as List<dynamic>).cast<String>(),
      ),
      versionLabel: row['version_label'] as String?,
      versionCharacteristics: (decodedVersionCharacteristics as List<dynamic>)
          .cast<String>()
          .map(SongVersionCharacteristic.values.byName)
          .toList(growable: false),
      releaseStatus: SongReleaseStatus.values.byName(
        row['release_status'] as String? ?? 'released',
      ),
      isLeak: (row['is_leak'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
