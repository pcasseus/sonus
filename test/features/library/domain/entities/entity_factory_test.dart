import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  group('EntityFactory', () {
    final now = DateTime.utc(2026, 9, 10, 12);

    test('creates artist with permanent ID and canonical name', () {
      final artist = EntityFactory.createArtist(
        name: '  Taylor   Swift  ',
        now: now,
      );

      expect(artist.id, startsWith('artist_'));
      expect(artist.name, 'Taylor   Swift');
      expect(artist.canonicalName, 'taylor swift');
      expect(artist.createdAt, now);
      expect(artist.updatedAt, now);
    });

    test('creates album linked to permanent artist ID', () {
      final album = EntityFactory.createAlbum(
        artistId: 'artist_test',
        title: '  The Tortured Poets Department  ',
        now: now,
      );

      expect(album.id, startsWith('album_'));
      expect(album.artistId, 'artist_test');
      expect(album.title, 'The Tortured Poets Department');
      expect(album.canonicalTitle, 'the tortured poets department');
    });

    test('creates album edition independently from album identity', () {
      final edition = EntityFactory.createAlbumEdition(
        albumId: 'album_test',
        title: 'Deluxe Edition',
        type: AlbumEditionType.deluxe,
        isPrimary: true,
        now: now,
      );

      expect(edition.id, startsWith('edition_'));
      expect(edition.albumId, 'album_test');
      expect(edition.type, AlbumEditionType.deluxe);
      expect(edition.isPrimary, isTrue);
    });

    test('creates song without any media file path', () {
      final song = EntityFactory.createSong(
        artistId: 'artist_test',
        albumId: 'album_test',
        albumEditionId: 'edition_test',
        title: '  Fortnight  ',
        trackNumber: 1,
        durationSeconds: 228,
        now: now,
      );

      expect(song.id, startsWith('song_'));
      expect(song.title, 'Fortnight');
      expect(song.canonicalTitle, 'fortnight');
      expect(song.artistId, 'artist_test');
      expect(song.albumId, 'album_test');
      expect(song.albumEditionId, 'edition_test');
    });

    test('creates song with structured version metadata', () {
      final song = EntityFactory.createSong(
        artistId: 'artist_test',
        albumId: 'album_test',
        albumEditionId: 'edition_test',
        title: 'Versioned Song',
        trackNumber: 4,
        durationSeconds: 205,
        versionLabel: '  Early Mix  ',
        versionCharacteristics: const [
          SongVersionCharacteristic.demo,
          SongVersionCharacteristic.acoustic,
        ],
        releaseStatus: SongReleaseStatus.unreleased,
        isLeak: true,
        now: now,
      );

      expect(song.versionLabel, 'Early Mix');
      expect(song.versionCharacteristics, const [
        SongVersionCharacteristic.demo,
        SongVersionCharacteristic.acoustic,
      ]);
      expect(song.releaseStatus, SongReleaseStatus.unreleased);
      expect(song.isLeak, isTrue);
    });

    test('createSong defaults version metadata safely', () {
      final song = EntityFactory.createSong(
        artistId: 'artist_test',
        albumId: 'album_test',
        albumEditionId: 'edition_test',
        title: 'Plain Song',
        trackNumber: 1,
        durationSeconds: 180,
        now: now,
      );

      expect(song.versionLabel, isNull);
      expect(song.versionCharacteristics, isEmpty);
      expect(song.releaseStatus, SongReleaseStatus.released);
      expect(song.isLeak, isFalse);
    });
    test('creates unique IDs for separate entities with identical names', () {
      final first = EntityFactory.createArtist(name: 'Same Artist', now: now);

      final second = EntityFactory.createArtist(name: 'Same Artist', now: now);

      expect(first.canonicalName, second.canonicalName);
      expect(first.id, isNot(second.id));
    });
  });
}
