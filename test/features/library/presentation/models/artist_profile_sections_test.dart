import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';

import '../pages/artist_profile_page_test.dart' as base;

// SN-48I: Top Tracks, Collaborations and Collaborators derivations.
void main() {
  group('topTracks', () {
    /// Ranks [plays] with the real all-time ranking service.
    Future<List<AnalyticsRankedEntity>> rank(
      Map<String, List<int>> plays,
    ) async {
      final repository = base.FakeQualifiedPlayRepository([
        for (final MapEntry(key: songId, value: days) in plays.entries)
          for (final day in days)
            base.qualifiedPlay(songId, at: DateTime.utc(2026, 1, day)),
      ]);
      final rankings =
          await AnalyticsEntityRankingService(qualifiedPlays: repository).load(
            period: AnalyticsPeriod.lifetime,
            referenceLocal: DateTime(2026, 6),
          );
      return rankings.songs;
    }

    final catalogue = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
        base.createTrack(songId: id, title: 'Song $id'),
    ];

    List<String> ids(List<ArtistTopTrack> top) => [
      for (final entry in top) entry.track.songId,
    ];

    test('orders by all-time streams and keeps at most five', () async {
      final top = ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: await rank({
          'a': [1],
          'b': [1, 2, 3, 4],
          'c': [1, 2],
          'd': [1, 2, 3],
          'e': [1, 2, 3, 4, 5, 6],
          'f': [1, 2, 3, 4, 5],
          'g': [1],
        }),
      );

      expect(ids(top), ['e', 'f', 'b', 'd', 'c']);
      expect([for (final entry in top) entry.streamCount], [6, 5, 4, 3, 2]);
    });

    test('breaks ties by the most recent stream, then by song ID', () async {
      final top = ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: await rank({
          'a': [1, 2],
          'b': [1, 9],
          'c': [3, 4],
          'd': [3, 4],
        }),
      );

      expect(ids(top), ['b', 'c', 'd', 'a']);
    });

    test('shows fewer than five, and none without streams', () async {
      expect(
        ids(
          ArtistProfileSections.topTracks(
            catalogue: catalogue,
            rankedSongs: await rank({
              'c': [1],
              'a': [1, 2],
            }),
          ),
        ),
        ['a', 'c'],
      );
      expect(
        ArtistProfileSections.topTracks(
          catalogue: catalogue,
          rankedSongs: await rank({}),
        ),
        isEmpty,
      );
    });

    test('only ranks the catalogue: other artists and featured-only songs '
        'are left out however much they are streamed', () async {
      final top = ArtistProfileSections.topTracks(
        catalogue: [base.createTrack(songId: 'mine')],
        rankedSongs: await rank({
          'someone-else': [1, 2, 3, 4, 5],
          'featured-only': [1, 2, 3],
          'mine': [1],
        }),
      );

      expect(ids(top), ['mine']);
    });

    test('leaves out blacklisted songs and keeps unavailable ones', () async {
      final top = ArtistProfileSections.topTracks(
        catalogue: [
          base.createTrack(songId: 'blocked', isSongBlocked: true),
          base.createTrack(songId: 'gone', filePath: '', isAvailable: false),
          base.createTrack(songId: 'here'),
        ],
        rankedSongs: await rank({
          'blocked': [1, 2, 3],
          'gone': [1, 2],
          'here': [1],
        }),
      );

      expect(ids(top), ['gone', 'here']);
      expect(top.first.streamCount, 2);
    });

    test('never invents a count', () {
      final top = ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: [
          AnalyticsRankedEntity(
            entityId: 'a',
            qualifiedStreamCount: 0,
            firstQualifiedAt: DateTime.utc(2026),
            lastQualifiedAt: DateTime.utc(2026),
          ),
        ],
      );

      expect(top, isEmpty);
    });
  });

  group('collaborations', () {
    test('lists featured credits and main credits on releases another '
        'artist owns, once each, by title', () {
      final collaborations = ArtistProfileSections.collaborations(
        mainTracks: [
          base.createTrack(songId: 'own', title: 'Own Album Song'),
          base.createTrack(
            songId: 'duet',
            title: 'Duet',
            artistId: 'other-artist',
            albumId: 'their-album',
          ),
          base.createTrack(
            songId: 'soundtrack',
            title: 'Soundtrack Song',
            albumId: 'soundtrack-album',
          ),
        ],
        featuredTracks: [
          base.createTrack(
            songId: 'guest',
            title: 'Guest Verse',
            artistId: 'other-artist',
            albumId: 'their-album',
          ),
          // Featured and co-primary on the same song: listed once.
          base.createTrack(
            songId: 'duet',
            title: 'Duet',
            artistId: 'other-artist',
            albumId: 'their-album',
          ),
        ],
        ownedAlbumIds: {'album-1'},
      );

      expect(
        [for (final track in collaborations) track.songId],
        ['duet', 'guest', 'soundtrack'],
      );
    });

    test('is empty for an artist with only their own releases', () {
      expect(
        ArtistProfileSections.collaborations(
          mainTracks: [base.createTrack()],
          featuredTracks: const [],
          ownedAlbumIds: {'album-1'},
        ),
        isEmpty,
      );
    });
  });

  group('collaborators', () {
    test('lists each performer once, by songs then name, with artwork', () {
      final collaborators = ArtistProfileSections.collaborators(
        projectArtistId: 'project',
        projectTracks: [
          base.createTrack(songId: 's1', artistId: 'zed', artistName: 'Zed'),
          base.createTrack(songId: 's2', artistId: 'amy', artistName: 'Amy'),
          base.createTrack(songId: 's3', artistId: 'zed', artistName: 'Zed'),
          base.createTrack(songId: 's3', artistId: 'zed', artistName: 'Zed'),
          base.createTrack(songId: 's4', artistId: 'bo', artistName: 'Bo'),
          base.createTrack(songId: 's5', artistId: 'project'),
        ],
        artistsById: {
          'amy': base.createArtist(
            artistId: 'amy',
            name: 'Amy',
            headerArtworkPath: '/art/amy.png',
          ),
        },
      );

      expect([for (final c in collaborators) c.artistId], ['zed', 'amy', 'bo']);
      expect(collaborators.first.tracks, hasLength(2));
      expect(collaborators[1].artworkPath, '/art/amy.png');
      // Without an artist record the credited track name is used.
      expect(collaborators.last.name, 'Bo');
    });

    test('is empty when the project artist performs every track', () {
      expect(
        ArtistProfileSections.collaborators(
          projectArtistId: 'artist-1',
          projectTracks: [base.createTrack()],
          artistsById: const {},
        ),
        isEmpty,
      );
    });
  });
}
