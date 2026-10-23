import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_record_equivalence.dart';
import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  final t = DateTime.utc(2026, 10, 23, 12, 0, 0, 0, 7);

  final state = CloudMetadataFieldState(
    fieldName: 'title',
    authority: 'manual',
    source: 'user',
    sourceReference: 'ref',
    updatedAt: t,
  );

  CloudSongRecord song({
    String userId = 'u1',
    String title = 'Song',
    int trackNumber = 1,
    int discNumber = 1,
    List<String> featuredArtists = const ['A', 'B'],
    List<String> versionCharacteristics = const ['live'],
    bool isBlocked = false,
    String? artworkId = 'art-1',
    DateTime? updatedAt,
    DateTime? deletedAt,
    List<CloudMetadataFieldState>? states,
    bool nullStates = false,
  }) {
    return CloudSongRecord(
      id: 'song-1',
      userId: userId,
      artistId: 'artist-1',
      albumId: 'album-1',
      albumEditionId: 'edition-1',
      title: title,
      canonicalTitle: 'song',
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationSeconds: 200,
      isSingle: false,
      isBlocked: isBlocked,
      featuredArtists: featuredArtists,
      versionLabel: 'Live',
      versionCharacteristics: versionCharacteristics,
      releaseStatus: 'released',
      isLeak: false,
      artworkId: artworkId,
      createdAt: t,
      updatedAt: updatedAt ?? t,
      deletedAt: deletedAt,
      metadataFieldStates: nullStates ? null : states ?? [state],
    );
  }

  test('identical records are equivalent across time zone forms', () {
    final shifted = song(updatedAt: t.toLocal());

    expect(CloudRecordEquivalence.isEquivalent(song(), shifted), isTrue);
  });

  final mutations = <String, CloudSongRecord>{
    'owner': song(userId: 'u2'),
    'title': song(title: 'Other'),
    'track number': song(trackNumber: 2),
    'disc number': song(discNumber: 2),
    'featured artist order': song(featuredArtists: const ['B', 'A']),
    'version characteristics': song(versionCharacteristics: const []),
    'blocked flag': song(isBlocked: true),
    'artwork reference': song(artworkId: null),
    'updated at by one microsecond': song(
      updatedAt: t.add(const Duration(microseconds: 1)),
    ),
    'tombstone': song(deletedAt: t),
    'provenance null versus empty': song(nullStates: true),
    'provenance empty versus present': song(states: const []),
    'provenance authority': song(
      states: [
        CloudMetadataFieldState(
          fieldName: 'title',
          authority: 'imported',
          source: 'user',
          sourceReference: 'ref',
          updatedAt: t,
        ),
      ],
    ),
  };

  for (final mutation in mutations.entries) {
    test('a differing ${mutation.key} is not equivalent', () {
      expect(
        CloudRecordEquivalence.isEquivalent(song(), mutation.value),
        isFalse,
      );
    });
  }

  test('a differing edition type is not equivalent', () {
    CloudAlbumEditionRecord edition(String type) => CloudAlbumEditionRecord(
      id: 'edition-1',
      userId: 'u1',
      albumId: 'album-1',
      title: 'Edition',
      type: type,
      isPrimary: true,
      createdAt: t,
      updatedAt: t,
    );

    expect(
      CloudRecordEquivalence.isEquivalent(
        edition('standard'),
        edition('deluxe'),
      ),
      isFalse,
    );
    expect(
      CloudRecordEquivalence.isEquivalent(
        edition('standard'),
        edition('standard'),
      ),
      isTrue,
    );
  });

  test('different record types are never equivalent', () {
    final album = CloudAlbumRecord(
      id: 'song-1',
      userId: 'u1',
      artistId: 'artist-1',
      title: 'Song',
      canonicalTitle: 'song',
      createdAt: t,
      updatedAt: t,
    );

    expect(CloudRecordEquivalence.isEquivalent(song(), album), isFalse);
  });

  test('the canonical form covers every synchronized wire column', () {
    final records = <CloudOwnedRecord>[
      CloudArtistRecord(
        id: 'a',
        userId: 'u1',
        name: 'A',
        canonicalName: 'a',
        createdAt: t,
        updatedAt: t,
      ),
      CloudAlbumRecord(
        id: 'b',
        userId: 'u1',
        artistId: 'a',
        title: 'B',
        canonicalTitle: 'b',
        createdAt: t,
        updatedAt: t,
      ),
      CloudAlbumEditionRecord(
        id: 'c',
        userId: 'u1',
        albumId: 'b',
        title: 'C',
        type: 'standard',
        isPrimary: true,
        createdAt: t,
        updatedAt: t,
      ),
      song(),
      CloudArtworkAssetRecord(
        id: 'd',
        userId: 'u1',
        storageObjectKey: 'u1/d.png',
        createdAt: t,
        updatedAt: t,
      ),
    ];

    for (final record in records) {
      final wireColumns = SupabaseCloudRecordMapper.toRow(record).keys.toSet()
        // A constant the client always writes; not a record field.
        ..remove('is_blacklisted');
      final canonicalFields = CloudRecordEquivalence.canonicalForm(
        record,
      ).keys.toSet()..remove(r'$recordType');

      expect(
        canonicalFields.length,
        wireColumns.length,
        reason: '${record.runtimeType} equivalence must compare every column',
      );
    }
  });
}
