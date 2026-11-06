// App Update 1.1 (Moments B): a song story shows the edition the song
// first appeared on; an album story shows the edition with the most songs.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/moment_edition_resolver.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_release_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/song_edition_membership.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

void main() {
  group('locket by Madison Beer: Standard (12) and Deluxe (15)', () {
    final album = _album(
      'locket',
      title: 'locket',
      artist: 'Madison Beer',
      primaryEditionId: 'locket-standard',
      artworkPath: '/art/locket-standard.jpg',
    );
    final standard = _edition(
      'locket-standard',
      albumId: 'locket',
      title: 'locket',
      primary: true,
      released: DateTime.utc(2026, 1, 16),
      tracks: 12,
      artworkPath: '/art/locket-standard.jpg',
    );
    final deluxe = _edition(
      'locket-deluxe',
      albumId: 'locket',
      title: 'locket (Deluxe)',
      type: AlbumEditionType.deluxe,
      released: DateTime.utc(2026, 5, 8),
      tracks: 15,
      artworkPath: '/art/locket-deluxe.jpg',
    );
    final editions = [standard, deluxe];
    final resolver = MomentEditionResolver(
      editions: editions,
      memberships: [
        for (var i = 1; i <= 12; i++) ...[
          _member('locket-$i', 'locket-standard'),
          _member('locket-$i', 'locket-deluxe'),
        ],
        for (var i = 13; i <= 15; i++) _member('locket-$i', 'locket-deluxe'),
      ],
    );

    test('the album story shows the Deluxe: it has more tracks', () {
      final presentation = MomentEditionResolver.albumPresentation(
        album,
        editions,
      );

      expect(presentation.title, 'locket (Deluxe)');
      expect(presentation.artworkPath, '/art/locket-deluxe.jpg');
      expect(presentation.editionId, 'locket-deluxe');
    });

    test('a song on both editions shows the Standard cover', () {
      final track = _track(
        'locket-3',
        albumId: 'locket',
        homeEditionId: 'locket-standard',
        artworkPath: '/art/song-own.jpg',
      );

      expect(
        resolver.songEdition(track, album: album)?.editionId,
        'locket-standard',
      );
      expect(
        resolver.songCover(track, album: album),
        '/art/locket-standard.jpg',
      );
      expect(resolver.songEditionTitle(track, album: album), 'locket');
    });

    test('a Deluxe-only song shows the Deluxe cover', () {
      final track = _track(
        'locket-14',
        albumId: 'locket',
        homeEditionId: 'locket-deluxe',
      );

      expect(resolver.songCover(track, album: album), '/art/locket-deluxe.jpg');
      expect(resolver.songEditionTitle(track, album: album), 'locket (Deluxe)');
    });

    test('equal counts: the album tie-break is deterministic (the Deluxe)', () {
      final tied = [
        _edition(
          'locket-standard',
          albumId: 'locket',
          title: 'locket',
          primary: true,
          released: DateTime.utc(2026, 1, 16),
          tracks: 12,
          artworkPath: '/art/locket-standard.jpg',
        ),
        _edition(
          'locket-deluxe',
          albumId: 'locket',
          title: 'locket (Deluxe)',
          type: AlbumEditionType.deluxe,
          released: DateTime.utc(2026, 5, 8),
          tracks: 12,
          artworkPath: '/art/locket-deluxe.jpg',
        ),
      ];

      for (final order in [tied, tied.reversed.toList()]) {
        final presentation = MomentEditionResolver.albumPresentation(
          album,
          order,
        );
        expect(presentation.editionId, 'locket-deluxe');
      }
    });
  });

  group('Midnight Sun by Zara Larsson: Standard and Girls Trip', () {
    final album = _album(
      'sun',
      title: 'Midnight Sun',
      artist: 'Zara Larsson',
      primaryEditionId: 'sun-standard',
      artworkPath: '/art/sun-standard.jpg',
    );
    final editions = [
      _edition(
        'sun-standard',
        albumId: 'sun',
        title: 'Midnight Sun',
        primary: true,
        released: DateTime.utc(2025, 9, 26),
        tracks: 11,
        artworkPath: '/art/sun-standard.jpg',
      ),
      _edition(
        'sun-girls-trip',
        albumId: 'sun',
        title: 'Midnight Sun (Girls Trip)',
        type: AlbumEditionType.deluxe,
        released: DateTime.utc(2026, 3, 13),
        tracks: 16,
        artworkPath: '/art/sun-girls-trip.jpg',
      ),
    ];
    final resolver = MomentEditionResolver(
      editions: editions,
      memberships: [
        _member('sun-1', 'sun-standard'),
        _member('sun-1', 'sun-girls-trip'),
        _member('sun-15', 'sun-girls-trip'),
      ],
    );

    test('the album story uses Girls Trip: it has more tracks', () {
      final presentation = MomentEditionResolver.albumPresentation(
        album,
        editions,
      );

      expect(presentation.title, 'Midnight Sun (Girls Trip)');
      expect(presentation.artworkPath, '/art/sun-girls-trip.jpg');
    });

    test('a Girls Trip-only song shows the Girls Trip cover', () {
      final track = _track(
        'sun-15',
        albumId: 'sun',
        homeEditionId: 'sun-girls-trip',
      );

      expect(
        resolver.songCover(track, album: album),
        '/art/sun-girls-trip.jpg',
      );
    });

    test('a song on both shows the Standard cover', () {
      final track = _track(
        'sun-1',
        albumId: 'sun',
        homeEditionId: 'sun-girls-trip',
      );

      expect(resolver.songCover(track, album: album), '/art/sun-standard.jpg');
      expect(resolver.songEditionTitle(track, album: album), 'Midnight Sun');
    });
  });

  group('ambiguous or missing dates fall back deterministically', () {
    final album = _album('a', primaryEditionId: 'a-primary');

    LibraryAlbumEdition? resolve(
      List<LibraryReleaseEdition> editions, {
      String homeEditionId = 'a-home',
    }) {
      final resolver = MomentEditionResolver(
        editions: editions,
        memberships: [
          for (final candidate in editions)
            _member('s', candidate.edition.editionId),
        ],
      );
      return resolver.songEdition(
        _track('s', albumId: 'a', homeEditionId: homeEditionId),
        album: album,
      );
    }

    test(
      '"2026" and "2026-05-01" may be the same day: the non-Deluxe wins',
      () {
        final winner = resolve([
          _edition(
            'a-deluxe',
            albumId: 'a',
            type: AlbumEditionType.deluxe,
            released: DateTime.utc(2026),
            precision: ReleaseDatePrecision.year,
          ),
          _edition(
            'a-standard',
            albumId: 'a',
            released: DateTime.utc(2026, 5, 1),
          ),
        ]);

        expect(winner?.editionId, 'a-standard');
      },
    );

    test('a vague date that is certainly later never wins', () {
      final winner = resolve([
        _edition(
          'a-deluxe',
          albumId: 'a',
          type: AlbumEditionType.deluxe,
          released: DateTime.utc(2025, 3, 1),
        ),
        _edition(
          'a-standard',
          albumId: 'a',
          released: DateTime.utc(2026),
          precision: ReleaseDatePrecision.year,
        ),
      ]);

      expect(winner?.editionId, 'a-deluxe');
    });

    test('a missing date: the non-Deluxe, then the primary edition', () {
      final winner = resolve([
        _edition(
          'a-deluxe',
          albumId: 'a',
          type: AlbumEditionType.deluxe,
          released: DateTime.utc(2020),
        ),
        _edition('a-other', albumId: 'a'),
        _edition(
          'a-primary',
          albumId: 'a',
          primary: true,
          released: DateTime.utc(2026, 4, 1),
        ),
      ]);

      expect(winner?.editionId, 'a-primary');
    });

    test('then the home edition', () {
      final winner = resolve([
        _edition('a-1', albumId: 'a', type: AlbumEditionType.expanded),
        _edition('a-home', albumId: 'a', type: AlbumEditionType.expanded),
      ]);

      expect(winner?.editionId, 'a-home');
    });

    test('then the edition added first, then the lowest id', () {
      final byAdded = resolve([
        _edition('a-1', albumId: 'a', added: DateTime.utc(2026, 9, 2)),
        _edition('a-2', albumId: 'a', added: DateTime.utc(2026, 9, 1)),
      ]);
      final byId = [
        _edition('a-2', albumId: 'a'),
        _edition('a-1', albumId: 'a'),
      ];

      expect(byAdded?.editionId, 'a-2');
      expect(resolve(byId)?.editionId, 'a-1');
      expect(resolve(byId.reversed.toList())?.editionId, 'a-1');
    });

    test('editions of another album are never used', () {
      final resolver = MomentEditionResolver(
        editions: [
          _edition(
            'other-ed',
            albumId: 'other',
            artworkPath: '/art/other.jpg',
            released: DateTime.utc(2000),
          ),
          _edition(
            'a-ed',
            albumId: 'a',
            artworkPath: '/art/a.jpg',
            released: DateTime.utc(2026),
          ),
        ],
        memberships: [_member('s', 'other-ed'), _member('s', 'a-ed')],
      );

      expect(
        resolver.songCover(_track('s', albumId: 'a', homeEditionId: 'a-ed')),
        '/art/a.jpg',
      );
    });

    test('a standalone single uses its own edition', () {
      final resolver = MomentEditionResolver(
        editions: [
          _edition(
            'single-ed',
            albumId: 'single',
            artworkPath: '/art/single.jpg',
          ),
        ],
        memberships: [_member('s', 'single-ed')],
      );

      expect(
        resolver.songCover(
          _track('s', albumId: 'single', homeEditionId: 'single-ed'),
        ),
        '/art/single.jpg',
      );
    });
  });

  group('artwork fallbacks', () {
    final album = _album(
      'a',
      primaryEditionId: 'a-primary',
      artworkPath: '/art/album.jpg',
    );
    final resolver = MomentEditionResolver(
      editions: [_edition('a-bare', albumId: 'a')],
      memberships: [_member('s', 'a-bare')],
    );

    test("an edition without a cover: the song's own artwork", () {
      final track = _track(
        's',
        albumId: 'a',
        homeEditionId: 'a-bare',
        artworkPath: '/art/song.jpg',
      );

      expect(resolver.songCover(track, album: album), '/art/song.jpg');
    });

    test("then the album's cover, then the placeholder", () {
      final track = _track('s', albumId: 'a', homeEditionId: 'a-bare');

      expect(resolver.songCover(track, album: album), '/art/album.jpg');
      expect(resolver.songCover(track), isNull);
    });

    test('memberships unknown: the home edition, else the old behaviour', () {
      final home = MomentEditionResolver(
        editions: [
          _edition('a-home', albumId: 'a', artworkPath: '/art/home.jpg'),
        ],
        memberships: const [],
      );
      final track = _track(
        's',
        albumId: 'a',
        homeEditionId: 'a-home',
        artworkPath: '/art/song.jpg',
      );

      expect(home.songCover(track, album: album), '/art/home.jpg');
      expect(
        MomentEditionResolver.empty().songCover(track, album: album),
        '/art/song.jpg',
      );
      expect(
        MomentEditionResolver.empty().songEditionTitle(track, album: album),
        isNull,
      );
    });
  });
}

SongEditionMembership _member(String songId, String editionId) =>
    SongEditionMembership(songId: songId, editionId: editionId);

LibraryAlbum _album(
  String id, {
  String title = 'Album',
  String artist = 'Artist',
  String? primaryEditionId,
  String? artworkPath,
}) => LibraryAlbum(
  albumId: id,
  title: title,
  artistId: 'artist-$id',
  artistName: artist,
  trackCount: 1,
  dateAdded: DateTime.utc(2026, 9, 1),
  artworkPath: artworkPath,
  primaryEditionId: primaryEditionId,
);

LibraryReleaseEdition _edition(
  String id, {
  required String albumId,
  String? title,
  AlbumEditionType type = AlbumEditionType.standard,
  bool primary = false,
  DateTime? released,
  ReleaseDatePrecision? precision,
  int tracks = 1,
  String? artworkPath,
  DateTime? added,
}) => LibraryReleaseEdition(
  edition: LibraryAlbumEdition(
    editionId: id,
    albumId: albumId,
    title: title ?? id,
    type: type,
    isPrimary: primary,
    dateAdded: added ?? DateTime.utc(2026, 9, 1),
    releaseDate: released,
    releaseDatePrecision: released == null
        ? null
        : precision ?? ReleaseDatePrecision.day,
    artworkPath: artworkPath,
  ),
  trackCount: tracks,
);

LibraryTrack _track(
  String id, {
  required String albumId,
  required String homeEditionId,
  String? artworkPath,
}) => LibraryTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist-1',
  artistName: 'Artist',
  albumId: albumId,
  albumTitle: 'Album',
  albumEditionId: homeEditionId,
  albumEditionTitle: 'Album',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime.utc(2026, 9, 1),
  isAvailable: true,
  filePath: 'C:/Music/$id.mp3',
  artworkPath: artworkPath,
);
