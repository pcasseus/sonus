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
      'artwork_id': song.artworkId,
      'featured_artists': jsonEncode(song.featuredArtists),
      'created_at': song.createdAt.toUtc().toIso8601String(),
      'updated_at': song.updatedAt.toUtc().toIso8601String(),
    };
  }

  static Song fromRow(Map<String, Object?> row) {
    final decodedFeaturedArtists = jsonDecode(
      row['featured_artists'] as String? ?? '[]',
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
      artworkId: row['artwork_id'] as String?,
      featuredArtists: List<String>.unmodifiable(
        (decodedFeaturedArtists as List<dynamic>).cast<String>(),
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
