import '../../domain/entities/song_artist_credit.dart';

abstract final class SongArtistCreditRowMapper {
  static Map<String, Object?> toRow(SongArtistCredit credit) {
    return {
      'id': credit.id,
      'song_id': credit.songId,
      'artist_id': credit.artistId,
      'credited_name': credit.creditedName,
      'canonical_credited_name': credit.canonicalCreditedName,
      'role': credit.role.name,
      'position': credit.position,
      'created_at': credit.createdAt.toUtc().toIso8601String(),
      'updated_at': credit.updatedAt.toUtc().toIso8601String(),
    };
  }

  static SongArtistCredit fromRow(Map<String, Object?> row) {
    return SongArtistCredit(
      id: row['id'] as String,
      songId: row['song_id'] as String,
      artistId: row['artist_id'] as String?,
      creditedName: row['credited_name'] as String,
      canonicalCreditedName: row['canonical_credited_name'] as String,
      role: SongArtistCreditRole.values.byName(row['role'] as String),
      position: row['position'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
