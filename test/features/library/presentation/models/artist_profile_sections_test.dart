import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_song_credit.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
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

    test('SN-50 B-Q35: with no limit, ranks every streamed song', () async {
      final top = ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: await rank({
          for (final (index, id) in ['a', 'b', 'c', 'd', 'e', 'f'].indexed)
            id: [for (var day = 1; day <= 6 - index; day++) day],
        }),
        limit: null,
      );

      expect(ids(top), ['a', 'b', 'c', 'd', 'e', 'f']);
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

  group('SN-50 release shelves', () {
    LibraryAlbum release(String id, {int tracks = 10}) => LibraryAlbum(
      albumId: id,
      title: 'Release $id',
      artistId: 'artist-1',
      artistName: 'Test Artist',
      trackCount: tracks,
      dateAdded: DateTime(2026),
    );

    Map<ArtistReleaseShelf, List<ArtistReleaseCard>> shelve(
      List<LibraryAlbum> albums, {
      Map<String, ReleaseFormat?> formats = const {},
      Set<String> stated = const {},
      Set<String> live = const {},
      Set<String> leaked = const {},
      Map<String, ReleaseKind> kinds = const {},
      Set<String> unavailable = const {},
    }) => ArtistProfileSections.releaseShelves(
      albums: albums,
      formatOf: (id) =>
          formats.containsKey(id) ? formats[id] : ReleaseFormat.album,
      hasStatedFormat: stated.contains,
      isLive: live.contains,
      isLeaked: leaked.contains,
      kindOf: (id) => kinds[id],
      isUnavailable: (album) => unavailable.contains(album.albumId),
    );

    List<String> ids(List<ArtistReleaseCard>? cards) => [
      for (final card in cards ?? const <ArtistReleaseCard>[])
        card.album.albumId,
    ];

    test('sections run Albums, EPs, Singles, Live, Leaked, Needs Review and '
        'list each release once, keeping the given order (B-Q8, B-Q25)', () {
      final shelves = shelve(
        [
          release('review', tracks: 2),
          release('leaked'),
          release('live'),
          release('single', tracks: 1),
          release('ep', tracks: 4),
          release('album-new'),
          release('album-old'),
        ],
        formats: {
          'review': null,
          'single': ReleaseFormat.single,
          'ep': ReleaseFormat.ep,
        },
        stated: {'single', 'ep', 'album-new', 'album-old', 'live', 'leaked'},
        live: {'live'},
        leaked: {'leaked'},
      );

      expect(shelves.keys, ArtistReleaseShelf.values);
      expect(ids(shelves[ArtistReleaseShelf.albums]), [
        'album-new',
        'album-old',
      ]);
      expect(ids(shelves[ArtistReleaseShelf.needsReview]), ['review']);
      final all = [for (final cards in shelves.values) ...ids(cards)];
      expect(all.toSet(), hasLength(all.length));
    });

    test('Leaked wins over Live and names Live on the card (B-Q7)', () {
      final shelves = shelve(
        [release('both')],
        stated: {'both'},
        live: {'both'},
        leaked: {'both'},
      );

      expect(shelves.keys, [ArtistReleaseShelf.leaked]);
      final card = shelves[ArtistReleaseShelf.leaked]!.single;
      expect(card.summary, 'Album · 10 tracks');
      expect(card.notes, ['Live']);
    });

    test('an unconfirmed Live or Leaked release stays in its section, '
        'flagged for review (B-Q14)', () {
      final shelves = shelve(
        [release('live', tracks: 1), release('leaked', tracks: 2)],
        formats: {'live': null, 'leaked': null},
        live: {'live'},
        leaked: {'leaked'},
      );

      final live = shelves[ArtistReleaseShelf.live]!.single;
      expect(live.summary, '1 track');
      expect(live.formatNeedsReview, isTrue);
      expect(live.notes, isEmpty);
      final leaked = shelves[ArtistReleaseShelf.leaked]!.single;
      expect(leaked.formatNeedsReview, isTrue);
      expect(leaked.notes, isEmpty);
      expect(shelves.containsKey(ArtistReleaseShelf.needsReview), isFalse);
    });

    test('an inferred Album stays an Album, flagged; a short unconfirmed '
        'release goes to Needs Review unflagged (B-Q37)', () {
      final shelves = shelve(
        [release('inferred', tracks: 8), release('short', tracks: 3)],
        formats: {'short': null},
      );

      final inferred = shelves[ArtistReleaseShelf.albums]!.single;
      expect(inferred.formatNeedsReview, isTrue);
      expect(inferred.notes, isEmpty);
      final review = shelves[ArtistReleaseShelf.needsReview]!.single;
      expect(review.summary, '3 tracks');
      expect(review.notes, isEmpty);
    });

    test('a soundtrack stays in its format section with its kind, and '
        'unavailable audio is marked, never hidden (B-Q23, B-Q24)', () {
      final shelves = shelve(
        [release('ost', tracks: 12)],
        formats: {'ost': ReleaseFormat.ep},
        stated: {'ost'},
        kinds: {'ost': ReleaseKind.soundtrack},
        unavailable: {'ost'},
      );

      final card = shelves[ArtistReleaseShelf.eps]!.single;
      expect(card.summary, 'EP · 12 tracks');
      expect(card.notes, ['Unavailable', 'Soundtrack']);
    });
  });

  group('SN-50 credited collaborators', () {
    ProjectSongCredit credit(
      String song,
      String? artist,
      SongArtistCreditRole role, {
      String? name,
    }) => ProjectSongCredit(
      albumId: 'album-1',
      songId: song,
      artistId: artist,
      creditedName: name ?? 'Name $artist',
      role: role,
    );

    final own = [
      base.createTrack(songId: 'one', title: 'One'),
      base.createTrack(songId: 'two', title: 'Two'),
    ];
    final byId = {for (final track in own) track.songId: track};

    test('featured and guest credits on the owner\'s own songs are '
        'collaborators, with their roles (B-Q15, B-Q32)', () {
      final result = ArtistProfileSections.creditedCollaborators(
        ownerArtistId: 'artist-1',
        credits: [
          credit('one', 'artist-1', SongArtistCreditRole.primary),
          credit('one', 'feat', SongArtistCreditRole.featured),
          credit('two', 'artist-1', SongArtistCreditRole.primary),
          credit('two', 'guest', SongArtistCreditRole.guest),
          credit('two', 'co', SongArtistCreditRole.coPrimary),
        ],
        projectTracks: own,
        tracksById: byId,
        artistsById: const {},
      );

      expect([for (final c in result) c.artistId], ['co', 'feat', 'guest']);
      expect(
        [for (final c in result) c.leadRole],
        [
          SongArtistCreditRole.coPrimary,
          SongArtistCreditRole.featured,
          SongArtistCreditRole.guest,
        ],
      );
      expect([for (final t in result[1].tracks) t.songId], ['one']);
    });

    test('a credit linked to no artist is listed once by its name, '
        'unverified (B-Q33)', () {
      final result = ArtistProfileSections.creditedCollaborators(
        ownerArtistId: 'artist-1',
        credits: [
          credit('one', null, SongArtistCreditRole.featured, name: 'Mo Vee'),
          credit('two', null, SongArtistCreditRole.featured, name: 'mo vee'),
        ],
        projectTracks: own,
        tracksById: byId,
        artistsById: const {},
      );

      final unverified = result.single;
      expect(unverified.isVerified, isFalse);
      expect(unverified.name, 'Mo Vee');
      expect(unverified.displaySongCount, 2);
      expect([for (final t in unverified.tracks) t.songId], ['one', 'two']);
    });

    test('Play covers every song credited on the releases, not just the '
        'ones they lead (B-Q26)', () {
      final result = ArtistProfileSections.creditedCollaborators(
        ownerArtistId: 'artist-1',
        credits: [
          credit('one', 'pal', SongArtistCreditRole.primary),
          credit('two', 'pal', SongArtistCreditRole.featured),
        ],
        projectTracks: own,
        tracksById: byId,
        artistsById: const {},
      );

      expect([for (final t in result.single.tracks) t.songId], ['one', 'two']);
      expect(result.single.roles, {
        SongArtistCreditRole.primary,
        SongArtistCreditRole.featured,
      });
    });

    test('a song without structured credits counts for its lead artist and '
        'its tagged featured names', () {
      final result = ArtistProfileSections.creditedCollaborators(
        ownerArtistId: 'artist-1',
        credits: const [],
        projectTracks: [
          base.createTrack(
            songId: 'old',
            artistId: 'lead',
            artistName: 'Lead Fixture',
            featuredArtists: ['Tagged Fixture'],
          ),
        ],
        tracksById: const {},
        artistsById: const {},
      );

      expect(
        [for (final c in result) (c.artistId, c.name)],
        [('lead', 'Lead Fixture'), (null, 'Tagged Fixture')],
      );
    });
  });
}
