import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  group('SupabaseCloudRecordMapper', () {
    final createdAt = DateTime.utc(2026, 9, 13, 10);
    final updatedAt = DateTime.utc(2026, 9, 13, 11);

    test('maps artist record to artists table and row', () {
      final record = CloudArtistRecord(
        id: 'artist_1',
        userId: 'user_1',
        name: 'Artist',
        canonicalName: 'artist',
        isBlacklisted: true,
        headerArtworkId: 'artwork_header',
        topArtistsArtworkId: 'artwork_top',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        SupabaseCloudRecordMapper.tableFor(record),
        SupabaseSyncContract.artistsTable,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(row[SupabaseSyncContract.idColumn], 'artist_1');
      expect(row[SupabaseSyncContract.userIdColumn], 'user_1');
      expect(row[SupabaseSyncContract.nameColumn], 'Artist');
      expect(row[SupabaseSyncContract.isBlacklistedColumn], isTrue);
      expect(row[SupabaseSyncContract.canonicalNameColumn], 'artist');
      expect(row[SupabaseSyncContract.headerArtworkIdColumn], 'artwork_header');
      expect(
        row[SupabaseSyncContract.topArtistsArtworkIdColumn],
        'artwork_top',
      );
      expect(row[SupabaseSyncContract.deletedAtColumn], isNull);
    });

    test('maps album record to albums table and row', () {
      final record = CloudAlbumRecord(
        id: 'album_1',
        userId: 'user_1',
        artistId: 'artist_1',
        title: 'Album',
        canonicalTitle: 'album',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        SupabaseCloudRecordMapper.tableFor(record),
        SupabaseSyncContract.albumsTable,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(row[SupabaseSyncContract.artistIdColumn], 'artist_1');
      expect(row[SupabaseSyncContract.titleColumn], 'Album');
      expect(row[SupabaseSyncContract.canonicalTitleColumn], 'album');
    });

    test('maps album edition record to album editions table and row', () {
      final releaseDate = DateTime.utc(2020, 1, 2);

      final record = CloudAlbumEditionRecord(
        id: 'edition_1',
        userId: 'user_1',
        albumId: 'album_1',
        title: 'Deluxe',
        type: 'deluxe',
        isPrimary: true,
        releaseDate: releaseDate,
        genre: 'Pop',
        artworkId: 'artwork_1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        SupabaseCloudRecordMapper.tableFor(record),
        SupabaseSyncContract.albumEditionsTable,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(row[SupabaseSyncContract.albumIdColumn], 'album_1');
      expect(row[SupabaseSyncContract.typeColumn], 'deluxe');
      expect(row[SupabaseSyncContract.isPrimaryColumn], isTrue);
      expect(
        row[SupabaseSyncContract.releaseDateColumn],
        releaseDate.toIso8601String(),
      );
      expect(row[SupabaseSyncContract.genreColumn], 'Pop');
      expect(row[SupabaseSyncContract.artworkIdColumn], 'artwork_1');
    });

    test('maps song record to songs table and row', () {
      final record = CloudSongRecord(
        id: 'song_1',
        userId: 'user_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        title: 'Song',
        canonicalTitle: 'song',
        trackNumber: 3,
        discNumber: 2,
        durationSeconds: 240,
        isSingle: false,
        featuredArtists: const ['Feature One', 'Feature Two'],
        artworkId: 'artwork_1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        SupabaseCloudRecordMapper.tableFor(record),
        SupabaseSyncContract.songsTable,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(row[SupabaseSyncContract.artistIdColumn], 'artist_1');
      expect(row[SupabaseSyncContract.albumIdColumn], 'album_1');
      expect(row[SupabaseSyncContract.albumEditionIdColumn], 'edition_1');
      expect(row[SupabaseSyncContract.trackNumberColumn], 3);
      expect(row[SupabaseSyncContract.discNumberColumn], 2);
      expect(row[SupabaseSyncContract.durationSecondsColumn], 240);
      expect(row[SupabaseSyncContract.isSingleColumn], isFalse);
      expect(row[SupabaseSyncContract.featuredArtistsColumn], const [
        'Feature One',
        'Feature Two',
      ]);
    });

    test('maps artwork asset record to artwork table and row', () {
      final record = CloudArtworkAssetRecord(
        id: 'artwork_1',
        userId: 'user_1',
        storageObjectKey: 'user_1/artwork_1.jpg',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(
        SupabaseCloudRecordMapper.tableFor(record),
        SupabaseSyncContract.artworkAssetsTable,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(
        row[SupabaseSyncContract.storageObjectKeyColumn],
        'user_1/artwork_1.jpg',
      );
    });

    test('serializes client timestamps as UTC ISO strings', () {
      final record = CloudArtistRecord(
        id: 'artist_1',
        userId: 'user_1',
        name: 'Artist',
        canonicalName: 'artist',
        isBlacklisted: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(
        row[SupabaseSyncContract.createdAtColumn],
        createdAt.toIso8601String(),
      );
      expect(
        row[SupabaseSyncContract.updatedAtColumn],
        updatedAt.toIso8601String(),
      );
    });

    test('serializes tombstone deletion timestamp', () {
      final deletedAt = DateTime.utc(2026, 9, 13, 12);

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

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(
        row[SupabaseSyncContract.deletedAtColumn],
        deletedAt.toIso8601String(),
      );
    });

    test('never sends server_updated_at from the client', () {
      final record = CloudArtistRecord(
        id: 'artist_1',
        userId: 'user_1',
        name: 'Artist',
        canonicalName: 'artist',
        isBlacklisted: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final row = SupabaseCloudRecordMapper.toRow(record);

      expect(
        row.containsKey(SupabaseSyncContract.serverUpdatedAtColumn),
        isFalse,
      );
    });
  });
}
