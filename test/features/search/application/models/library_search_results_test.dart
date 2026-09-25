import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/search/application/models/library_search_results.dart';

void main() {
  group('LibrarySearchResults', () {
    test('empty result reports no matches', () {
      const results = LibrarySearchResults();

      expect(results.isEmpty, isTrue);
      expect(results.isNotEmpty, isFalse);
      expect(results.totalCount, 0);
    });

    test('reports grouped result count', () {
      final results = LibrarySearchResults(
        artists: [
          LibraryArtist(
            artistId: 'artist-1',
            name: 'Search Artist',
            albumCount: 1,
            songCount: 1,
            dateAdded: DateTime.utc(2026, 9, 25),
          ),
        ],
        albums: [
          LibraryAlbum(
            albumId: 'album-1',
            title: 'Search Album',
            artistId: 'artist-1',
            artistName: 'Search Artist',
            trackCount: 1,
            dateAdded: DateTime.utc(2026, 9, 25),
          ),
        ],
        tracks: [
          LibraryTrack(
            songId: 'song-1',
            title: 'Search Song',
            artistId: 'artist-1',
            artistName: 'Search Artist',
            albumId: 'album-1',
            albumTitle: 'Search Album',
            albumEditionId: 'edition-1',
            albumEditionTitle: 'Search Album',
            albumEditionType: AlbumEditionType.standard,
            trackNumber: 1,
            durationSeconds: 180,
            isSingle: false,
            featuredArtists: const [],
            dateAdded: DateTime.utc(2026, 9, 25),
            isAvailable: true,
            filePath: r'C:\Music\Search Song.mp3',
          ),
        ],
      );

      expect(results.isEmpty, isFalse);
      expect(results.isNotEmpty, isTrue);
      expect(results.totalCount, 3);
    });
  });
}
