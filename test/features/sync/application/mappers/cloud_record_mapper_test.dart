import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/mappers/cloud_record_mapper.dart';

void main() {
  group('CloudRecordMapper', () {
    final createdAt = DateTime.utc(2026, 1, 2);
    final updatedAt = DateTime.utc(2026, 1, 3);

    test('maps artist logical data and user ownership', () {
      final artist = Artist(
        id: 'artist_1',
        name: 'Artist',
        canonicalName: 'artist',
        headerArtworkId: 'artwork_1',
        topArtistsArtworkId: 'artwork_2',
        isBlacklisted: true,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final record = CloudRecordMapper.artist(artist: artist, userId: 'user_1');

      expect(record.id, artist.id);
      expect(record.userId, 'user_1');
      expect(record.name, artist.name);
      expect(record.headerArtworkId, artist.headerArtworkId);
      expect(record.isBlacklisted, isTrue);
    });

    test('maps album relationship data', () {
      final album = Album(
        id: 'album_1',
        artistId: 'artist_1',
        title: 'Album',
        canonicalTitle: 'album',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final record = CloudRecordMapper.album(album: album, userId: 'user_1');

      expect(record.artistId, album.artistId);
      expect(record.canonicalTitle, album.canonicalTitle);
    });

    test('maps album edition enum using stable enum name', () {
      final edition = AlbumEdition(
        id: 'edition_1',
        albumId: 'album_1',
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        isPrimary: true,
        releaseDate: DateTime.utc(2020, 1, 1),
        genre: 'Pop',
        artworkId: 'artwork_1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final record = CloudRecordMapper.albumEdition(
        albumEdition: edition,
        userId: 'user_1',
      );

      expect(record.type, 'deluxe');
      expect(record.albumId, edition.albumId);
      expect(record.artworkId, edition.artworkId);
    });

    test(
      'maps song logical metadata without requiring a media file binding',
      () {
        final song = Song(
          id: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_1',
          title: 'Song',
          canonicalTitle: 'song',
          trackNumber: 4,
          durationSeconds: 215,
          isSingle: false,
          featuredArtists: const ['Feature'],
          artworkId: 'artwork_1',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final record = CloudRecordMapper.song(song: song, userId: 'user_1');

        expect(record.id, song.id);
        expect(record.albumEditionId, song.albumEditionId);
        expect(record.featuredArtists, const ['Feature']);
        expect(record.durationSeconds, 215);
      },
    );

    test(
      'artwork mapping uses cloud storage key instead of local file path',
      () {
        final artwork = ArtworkAsset(
          id: 'artwork_1',
          filePath: r'C:\local\sonus\artwork\image.jpg',
          normalizedPath: 'c:/local/sonus/artwork/image.jpg',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final record = CloudRecordMapper.artworkAsset(
          artworkAsset: artwork,
          userId: 'user_1',
          storageObjectKey: 'user_1/artwork_1.jpg',
        );

        expect(record.storageObjectKey, 'user_1/artwork_1.jpg');
        expect(record.storageObjectKey, isNot(artwork.filePath));
        expect(record.storageObjectKey, isNot(artwork.normalizedPath));
      },
    );

    test('rejects blank cloud artwork storage object key', () {
      final artwork = ArtworkAsset(
        id: 'artwork_1',
        filePath: '/local/artwork.jpg',
        normalizedPath: '/local/artwork.jpg',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        () => CloudRecordMapper.artworkAsset(
          artworkAsset: artwork,
          userId: 'user_1',
          storageObjectKey: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}
