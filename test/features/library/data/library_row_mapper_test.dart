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

  test('artist mapper ignores retired blacklist storage state', () {
    final artist = Artist(
      id: 'artist_1',
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = ArtistRowMapper.toRow(artist);

    expect(row.containsKey('is_blacklisted'), isFalse);

    final restored = ArtistRowMapper.fromRow({...row, 'is_blacklisted': 1});

    expect(restored.id, artist.id);
    expect(restored.name, artist.name);
    expect(restored.canonicalName, artist.canonicalName);
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

  test('song round trip preserves structured version metadata', () {
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
      versionLabel: 'Festival Mix',
      versionCharacteristics: const [
        SongVersionCharacteristic.live,
        SongVersionCharacteristic.remix,
      ],
      releaseStatus: SongReleaseStatus.unreleased,
      isLeak: true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = SongRowMapper.toRow(song);
    final restored = SongRowMapper.fromRow(row);

    expect(restored, song);
    expect(restored.featuredArtists, ['Guest One', 'Guest Two']);
    expect(restored.trackNumber, 2);
    expect(restored.durationSeconds, 241);
    expect(restored.isSingle, isTrue);
    expect(restored.versionLabel, 'Festival Mix');
    expect(restored.versionCharacteristics, const [
      SongVersionCharacteristic.live,
      SongVersionCharacteristic.remix,
    ]);
    expect(restored.releaseStatus, SongReleaseStatus.unreleased);
    expect(restored.isLeak, isTrue);
  });

  test('song mapper defaults missing version metadata for legacy rows', () {
    final row = <String, Object?>{
      'id': 'song_legacy',
      'artist_id': 'artist_1',
      'album_id': 'album_1',
      'album_edition_id': 'edition_1',
      'title': 'Legacy Song',
      'canonical_title': 'legacy song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'is_blocked': 0,
      'featured_artists': '[]',
      'artwork_id': null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    final restored = SongRowMapper.fromRow(row);

    expect(restored.versionLabel, isNull);
    expect(restored.versionCharacteristics, isEmpty);
    expect(restored.releaseStatus, SongReleaseStatus.released);
    expect(restored.isLeak, isFalse);
  });
}
