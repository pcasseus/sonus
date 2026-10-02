import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/data/mappers/album_edition_track_row_mapper.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';

void main() {
  test('round trips manual membership authority', () {
    final createdAt = DateTime.utc(2026, 10, 2, 10);
    final updatedAt = DateTime.utc(2026, 10, 2, 11);

    final membership = AlbumEditionTrack(
      albumEditionId: 'edition-1',
      songId: 'song-1',
      discNumber: 2,
      trackNumber: 7,
      sortPosition: 4,
      numberingAuthority: AlbumEditionTrackAuthority.manual,
      orderingAuthority: AlbumEditionTrackAuthority.manual,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = AlbumEditionTrackRowMapper.toRow(membership);

    expect(row['numbering_authority'], 'manual');
    expect(row['ordering_authority'], 'manual');

    final restored = AlbumEditionTrackRowMapper.fromRow(row);

    expect(restored.albumEditionId, 'edition-1');
    expect(restored.songId, 'song-1');
    expect(restored.discNumber, 2);
    expect(restored.trackNumber, 7);
    expect(restored.sortPosition, 4);
    expect(restored.numberingAuthority, AlbumEditionTrackAuthority.manual);
    expect(restored.orderingAuthority, AlbumEditionTrackAuthority.manual);
    expect(restored.createdAt.toUtc(), createdAt);
    expect(restored.updatedAt.toUtc(), updatedAt);
  });

  test('legacy row without authority fields defaults to inferred', () {
    final timestamp = DateTime.utc(2026, 10, 2).toIso8601String();

    final restored = AlbumEditionTrackRowMapper.fromRow({
      'album_edition_id': 'edition-1',
      'song_id': 'song-1',
      'disc_number': 1,
      'track_number': 1,
      'sort_position': 0,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    expect(restored.numberingAuthority, AlbumEditionTrackAuthority.inferred);
    expect(restored.orderingAuthority, AlbumEditionTrackAuthority.inferred);
  });

  test('rejects unsupported persisted membership authority', () {
    final timestamp = DateTime.utc(2026, 10, 2).toIso8601String();

    expect(
      () => AlbumEditionTrackRowMapper.fromRow({
        'album_edition_id': 'edition-1',
        'song_id': 'song-1',
        'disc_number': 1,
        'track_number': 1,
        'sort_position': 0,
        'numbering_authority': 'unknown',
        'ordering_authority': 'inferred',
        'created_at': timestamp,
        'updated_at': timestamp,
      }),
      throwsA(isA<StateError>()),
    );
  });
}
