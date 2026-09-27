import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  group('SupabaseCloudRecordMapper.fromRow', () {
    test('maps artist row and preserves server sync timestamp', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.artist,
        row: {
          'id': 'artist-1',
          'user_id': 'user-1',
          'name': 'Artist Name',
          'canonical_name': 'artist name',
          'is_blacklisted': true,
          'header_artwork_id': 'artwork-header',
          'top_artists_artwork_id': 'artwork-top',
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      expect(item.record, isA<CloudArtistRecord>());
      expect(
        item.serverUpdatedAt,
        DateTime.parse('2026-09-12T12:00:00.000Z').toUtc(),
      );

      final record = item.record as CloudArtistRecord;

      expect(record.id, 'artist-1');
      expect(record.userId, 'user-1');
      expect(record.name, 'Artist Name');
      expect(record.canonicalName, 'artist name');
      expect(record.headerArtworkId, 'artwork-header');
      expect(record.topArtistsArtworkId, 'artwork-top');
      expect(record.deletedAt, isNull);
    });

    test('maps album row', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.album,
        row: {
          'id': 'album-1',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'title': 'Album Title',
          'canonical_title': 'album title',
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      final record = item.record as CloudAlbumRecord;

      expect(record.id, 'album-1');
      expect(record.artistId, 'artist-1');
      expect(record.title, 'Album Title');
      expect(record.canonicalTitle, 'album title');
    });

    test('maps album edition row', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.albumEdition,
        row: {
          'id': 'edition-1',
          'user_id': 'user-1',
          'album_id': 'album-1',
          'title': 'Deluxe',
          'type': 'deluxe',
          'is_primary': false,
          'release_date': '2026-08-01T00:00:00.000Z',
          'genre': 'Pop',
          'artwork_id': 'artwork-1',
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      final record = item.record as CloudAlbumEditionRecord;

      expect(record.id, 'edition-1');
      expect(record.albumId, 'album-1');
      expect(record.title, 'Deluxe');
      expect(record.type, 'deluxe');
      expect(record.isPrimary, isFalse);
      expect(record.genre, 'Pop');
      expect(record.artworkId, 'artwork-1');
      expect(
        record.releaseDate,
        DateTime.parse('2026-08-01T00:00:00.000Z').toUtc(),
      );
    });

    test('maps song row including Postgres text array', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.song,
        row: {
          'id': 'song-1',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'edition-1',
          'title': 'Song Title',
          'canonical_title': 'song title',
          'track_number': 4,
          'disc_number': 3,
          'duration_seconds': 245,
          'is_single': true,
          'featured_artists': ['Feature One', 'Feature Two'],
          'artwork_id': 'artwork-1',
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      final record = item.record as CloudSongRecord;

      expect(record.id, 'song-1');
      expect(record.artistId, 'artist-1');
      expect(record.albumId, 'album-1');
      expect(record.albumEditionId, 'edition-1');
      expect(record.trackNumber, 4);
      expect(record.discNumber, 3);
      expect(record.durationSeconds, 245);
      expect(record.isSingle, isTrue);
      expect(record.featuredArtists, ['Feature One', 'Feature Two']);
      expect(record.artworkId, 'artwork-1');
    });

    test('historical song row without disc number defaults to one', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.song,
        row: {
          'id': 'song-legacy',
          'user_id': 'user-1',
          'artist_id': 'artist-1',
          'album_id': 'album-1',
          'album_edition_id': 'edition-1',
          'title': 'Legacy Song',
          'canonical_title': 'legacy song',
          'track_number': 9,
          'duration_seconds': 180,
          'is_single': false,
          'featured_artists': <String>[],
          'artwork_id': null,
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      final record = item.record as CloudSongRecord;

      expect(record.trackNumber, 9);
      expect(record.discNumber, 1);
    });
    test('maps artwork row', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.artworkAsset,
        row: {
          'id': 'artwork-1',
          'user_id': 'user-1',
          'storage_object_key': 'user-1/artwork-1.jpg',
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-11T11:00:00.000Z',
          'server_updated_at': '2026-09-12T12:00:00.000Z',
          'deleted_at': null,
        },
      );

      final record = item.record as CloudArtworkAssetRecord;

      expect(record.id, 'artwork-1');
      expect(record.storageObjectKey, 'user-1/artwork-1.jpg');
    });

    test('preserves cloud tombstone', () {
      final item = SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.artist,
        row: {
          'id': 'artist-deleted',
          'user_id': 'user-1',
          'name': 'Deleted Artist',
          'canonical_name': 'deleted artist',
          'is_blacklisted': false,
          'header_artwork_id': null,
          'top_artists_artwork_id': null,
          'created_at': '2026-09-10T10:00:00.000Z',
          'updated_at': '2026-09-13T08:00:00.000Z',
          'server_updated_at': '2026-09-13T08:00:01.000Z',
          'deleted_at': '2026-09-13T08:00:00.000Z',
        },
      );

      final record = item.record as CloudArtistRecord;

      expect(
        record.deletedAt,
        DateTime.parse('2026-09-13T08:00:00.000Z').toUtc(),
      );
      expect(
        item.serverUpdatedAt,
        DateTime.parse('2026-09-13T08:00:01.000Z').toUtc(),
      );
    });

    test('rejects malformed disc number', () {
      expect(
        () => SupabaseCloudRecordMapper.fromRow(
          entityType: CloudDataEntity.song,
          row: {
            'id': 'song-1',
            'user_id': 'user-1',
            'artist_id': 'artist-1',
            'album_id': 'album-1',
            'album_edition_id': 'edition-1',
            'title': 'Song Title',
            'canonical_title': 'song title',
            'track_number': 1,
            'disc_number': 'two',
            'duration_seconds': 200,
            'is_single': false,
            'featured_artists': <String>[],
            'artwork_id': null,
            'created_at': '2026-09-10T10:00:00.000Z',
            'updated_at': '2026-09-11T11:00:00.000Z',
            'server_updated_at': '2026-09-12T12:00:00.000Z',
            'deleted_at': null,
          },
        ),
        throwsStateError,
      );
    });
    test('rejects malformed featured artist arrays', () {
      expect(
        () => SupabaseCloudRecordMapper.fromRow(
          entityType: CloudDataEntity.song,
          row: {
            'id': 'song-1',
            'user_id': 'user-1',
            'artist_id': 'artist-1',
            'album_id': 'album-1',
            'album_edition_id': 'edition-1',
            'title': 'Song Title',
            'canonical_title': 'song title',
            'track_number': 1,
            'duration_seconds': 200,
            'is_single': false,
            'featured_artists': ['Valid Artist', 42],
            'artwork_id': null,
            'created_at': '2026-09-10T10:00:00.000Z',
            'updated_at': '2026-09-11T11:00:00.000Z',
            'server_updated_at': '2026-09-12T12:00:00.000Z',
            'deleted_at': null,
          },
        ),
        throwsStateError,
      );
    });

    test('rejects a row missing server_updated_at', () {
      expect(
        () => SupabaseCloudRecordMapper.fromRow(
          entityType: CloudDataEntity.artist,
          row: {
            'id': 'artist-1',
            'user_id': 'user-1',
            'name': 'Artist Name',
            'canonical_name': 'artist name',
            'is_blacklisted': false,
            'header_artwork_id': null,
            'top_artists_artwork_id': null,
            'created_at': '2026-09-10T10:00:00.000Z',
            'updated_at': '2026-09-11T11:00:00.000Z',
            'deleted_at': null,
          },
        ),
        throwsStateError,
      );
    });
  });
}
