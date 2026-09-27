import 'dart:convert';

import '../../application/models/library_track.dart';
import '../../domain/entities/album_edition.dart';

abstract final class LibraryTrackRowMapper {
  static LibraryTrack fromRow(Map<String, Object?> row) {
    final decodedFeaturedArtists = jsonDecode(
      row['featured_artists'] as String? ?? '[]',
    );

    final editionTypeName = row['edition_type'] as String?;

    final editionType = AlbumEditionType.values.firstWhere(
      (value) => value.name == editionTypeName,
      orElse: () => AlbumEditionType.other,
    );

    return LibraryTrack(
      songId: row['song_id'] as String,
      title: row['song_title'] as String,
      artistId: row['artist_id'] as String,
      artistName: row['artist_name'] as String,
      albumId: row['album_id'] as String,
      albumTitle: row['album_title'] as String,
      albumEditionId: row['album_edition_id'] as String,
      albumEditionTitle: row['album_edition_title'] as String,
      albumEditionType: editionType,
      trackNumber: row['track_number'] as int? ?? 0,
      discNumber: row['disc_number'] as int? ?? 1,
      durationSeconds: row['duration_seconds'] as int? ?? 0,
      artworkId: row['artwork_id'] as String?,
      artworkPath: row['artwork_path'] as String?,
      isSingle: (row['is_single'] as int? ?? 0) == 1,
      featuredArtists: List<String>.unmodifiable(
        (decodedFeaturedArtists as List<dynamic>).cast<String>(),
      ),
      dateAdded: DateTime.parse(row['created_at'] as String),
      filePath: row['file_path'] as String?,
      isAvailable: (row['is_available'] as int? ?? 0) == 1,
      isSongBlocked: (row['song_is_blocked'] as int? ?? 0) == 1,
      isArtistBlacklisted: (row['artist_is_blacklisted'] as int? ?? 0) == 1,
    );
  }
}
