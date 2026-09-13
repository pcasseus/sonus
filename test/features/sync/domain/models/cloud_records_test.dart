import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  group('cloud records', () {
    final createdAt = DateTime.utc(2026, 1, 2);
    final updatedAt = DateTime.utc(2026, 1, 3);

    test('artist record carries user ownership and logical identifiers', () {
      final record = CloudArtistRecord(
        id: 'artist_1',
        userId: 'user_1',
        name: 'Artist',
        canonicalName: 'artist',
        isBlacklisted: true,
        headerArtworkId: 'artwork_1',
        topArtistsArtworkId: 'artwork_2',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(record.id, 'artist_1');
      expect(record.userId, 'user_1');
      expect(record.isBlacklisted, isTrue);
      expect(record.headerArtworkId, 'artwork_1');
      expect(record.topArtistsArtworkId, 'artwork_2');
      expect(record.createdAt, createdAt);
      expect(record.updatedAt, updatedAt);
    });

    test('album record preserves artist relationship', () {
      final record = CloudAlbumRecord(
        id: 'album_1',
        userId: 'user_1',
        artistId: 'artist_1',
        title: 'Album',
        canonicalTitle: 'album',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(record.artistId, 'artist_1');
    });

    test('album edition record preserves album and artwork relationships', () {
      final record = CloudAlbumEditionRecord(
        id: 'edition_1',
        userId: 'user_1',
        albumId: 'album_1',
        title: 'Deluxe',
        type: 'deluxe',
        isPrimary: true,
        artworkId: 'artwork_1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(record.albumId, 'album_1');
      expect(record.artworkId, 'artwork_1');
      expect(record.isPrimary, isTrue);
    });

    test('song record contains logical metadata but no device file path', () {
      final record = CloudSongRecord(
        id: 'song_1',
        userId: 'user_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        title: 'Song',
        canonicalTitle: 'song',
        trackNumber: 1,
        durationSeconds: 180,
        isSingle: false,
        featuredArtists: const ['Featured Artist'],
        artworkId: 'artwork_1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(record.albumEditionId, 'edition_1');
      expect(record.durationSeconds, 180);
      expect(record.featuredArtists, const ['Featured Artist']);
    });

    test('artwork cloud record uses storage object key', () {
      final record = CloudArtworkAssetRecord(
        id: 'artwork_1',
        userId: 'user_1',
        storageObjectKey: 'user_1/artwork_1.jpg',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(record.storageObjectKey, 'user_1/artwork_1.jpg');
    });

    test('tombstone marks a cloud record as deleted', () {
      final deletedAt = DateTime.utc(2026, 1, 4);

      final record = CloudArtistRecord(
        id: 'artist_1',
        userId: 'user_1',
        name: 'Artist',
        canonicalName: 'artist',
        isBlacklisted: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

      expect(record.deletedAt, deletedAt);
      expect(record.isDeleted, isTrue);
    });
  });
}
