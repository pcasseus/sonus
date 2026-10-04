import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/data/mappers/song_artist_credit_row_mapper.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';

void main() {
  test('round-trips structured song artist credit rows', () {
    final createdAt = DateTime.utc(2026, 10, 1, 12);
    final updatedAt = DateTime.utc(2026, 10, 1, 13);

    final credit = SongArtistCredit(
      id: 'credit_1',
      songId: 'song_1',
      artistId: 'artist_1',
      creditedName: 'Beyoncé',
      canonicalCreditedName: 'beyoncé',
      role: SongArtistCreditRole.primary,
      position: 0,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = SongArtistCreditRowMapper.toRow(credit);
    final restored = SongArtistCreditRowMapper.fromRow(row);

    expect(restored.id, credit.id);
    expect(restored.songId, credit.songId);
    expect(restored.artistId, credit.artistId);
    expect(restored.creditedName, credit.creditedName);
    expect(restored.canonicalCreditedName, credit.canonicalCreditedName);
    expect(restored.role, credit.role);
    expect(restored.position, credit.position);
    expect(restored.createdAt.toUtc(), createdAt);
    expect(restored.updatedAt.toUtc(), updatedAt);
  });

  test('supports unlinked featured credits', () {
    final timestamp = DateTime.utc(2026, 10, 1);

    final credit = SongArtistCredit(
      id: 'credit_feature',
      songId: 'song_1',
      creditedName: 'Jack White',
      canonicalCreditedName: 'jack white',
      role: SongArtistCreditRole.featured,
      position: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final row = SongArtistCreditRowMapper.toRow(credit);
    final restored = SongArtistCreditRowMapper.fromRow(row);

    expect(restored.artistId, isNull);
    expect(restored.isLinkedToLibraryArtist, isFalse);
    expect(restored.role, SongArtistCreditRole.featured);
  });
}
