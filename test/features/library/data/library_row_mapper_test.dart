import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/data/mappers/album_edition_row_mapper.dart';
import 'package:sonus_next/features/library/data/mappers/album_row_mapper.dart';
import 'package:sonus_next/features/library/data/mappers/artist_row_mapper.dart';
import 'package:sonus_next/features/library/data/mappers/song_row_mapper.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10, 12);
  final updatedAt = DateTime.utc(2026, 9, 10, 13);

  test('artist round trip preserves blacklist state', () {
    final artist = Artist(
      id: 'artist_1',
      name: 'Artist',
      canonicalName: 'artist',
      isBlacklisted: true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = ArtistRowMapper.toRow(artist);
    final restored = ArtistRowMapper.fromRow(row);

    expect(row['is_blacklisted'], 1);
    expect(restored.id, artist.id);
    expect(restored.isBlacklisted, isTrue);
  });

  test('artist mapper treats missing blacklist state as false', () {
    final restored = ArtistRowMapper.fromRow({
      'id': 'artist_legacy',
      'name': 'Legacy Artist',
      'canonical_name': 'legacy artist',
      'header_artwork_id': null,
      'top_artists_artwork_id': null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    });

    expect(restored.isBlacklisted, isFalse);
  });

  test('album round trips through SQLite row mapper', () {
    final album = Album(
      id: 'album_1',
      artistId: 'artist_1',
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(AlbumRowMapper.fromRow(AlbumRowMapper.toRow(album)), album);
  });

  test('album edition preserves nullable metadata', () {
    final edition = AlbumEdition(
      id: 'edition_1',
      albumId: 'album_1',
      title: 'Deluxe',
      type: AlbumEditionType.deluxe,
      isPrimary: false,
      releaseDate: DateTime.utc(2026, 9, 1),
      genre: 'Pop',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final restored = AlbumEditionRowMapper.fromRow(
      AlbumEditionRowMapper.toRow(edition),
    );

    expect(restored, edition);
    expect(restored.releaseDate, edition.releaseDate);
    expect(restored.genre, 'Pop');
    expect(restored.type, AlbumEditionType.deluxe);
  });

  test('song round trip preserves featured artists', () {
    final song = Song(
      id: 'song_1',
      artistId: 'artist_1',
      albumId: 'album_1',
      albumEditionId: 'edition_1',
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 2,
      durationSeconds: 241,
      isSingle: true,
      featuredArtists: const ['Guest One', 'Guest Two'],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final restored = SongRowMapper.fromRow(SongRowMapper.toRow(song));

    expect(restored, song);
    expect(restored.featuredArtists, ['Guest One', 'Guest Two']);
    expect(restored.trackNumber, 2);
    expect(restored.durationSeconds, 241);
    expect(restored.isSingle, isTrue);
  });
}
