import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';

import '../pages/artist_profile_page_test.dart' as base;

// App Update 1.3 (post-preview correction): songs marked as Singles are
// cards in the Singles rail, ordered with the Single releases by each one's
// own release date.
ArtistReleaseCard _release(
  String id,
  String title, {
  DateTime? released,
  ReleaseDatePrecision? precision,
  String? artworkPath,
}) => ArtistReleaseCard(
  album: LibraryAlbum(
    albumId: id,
    title: title,
    artistId: 'artist-1',
    artistName: 'Test Artist',
    trackCount: 1,
    releaseDate: released,
    releaseDatePrecision: precision,
    artworkPath: artworkPath,
    dateAdded: DateTime(2026),
  ),
  format: ReleaseFormat.single,
);

SongSinglePresentation _single(
  String songId, {
  ReleaseDate? date,
  String? cover,
}) => SongSinglePresentation(
  songId: songId,
  releaseDate: date,
  artworkId: cover == null ? null : 'art-$songId',
  artworkPath: cover,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

List<String> _ids(List<ArtistRailCard> rail) => [
  for (final card in rail) card.stableId,
];

void main() {
  test('one collection, newest first by each item\'s own date; the '
      'releases keep their order', () {
    final rail = ArtistProfileSections.singlesRail(
      releases: [
        _release('r-2025', '15 Minutes', released: DateTime(2025, 1, 10)),
        _release(
          'r-2023',
          'I Have Never Felt More Alive',
          released: DateTime(2023, 2, 1),
        ),
      ],
      songs: [
        base.createTrack(songId: 's-2024', title: 'bittersweet'),
        base.createTrack(songId: 's-2026', title: 'Newest'),
      ],
      presentations: {
        's-2024': _single('s-2024', date: ReleaseDate.of(2024, 4, 5)),
        's-2026': _single('s-2026', date: ReleaseDate.of(2026)),
      },
    );

    expect(_ids(rail), [
      'song:s-2026',
      'album:r-2025',
      'song:s-2024',
      'album:r-2023',
    ]);
  });

  test('ties: same date sorts by title, then release before song, then '
      'ID; the order never depends on input order', () {
    final releases = [
      _release('r-b', 'Same', released: DateTime(2024, 4, 5)),
      _release('r-a', 'Zed', released: DateTime(2024, 4, 5)),
    ]..sort(ArtistProfileSections.compareRailCards);
    final songs = [
      base.createTrack(songId: 's-2', title: 'Same'),
      base.createTrack(songId: 's-1', title: 'Same'),
      base.createTrack(songId: 's-0', title: 'alpha'),
    ];
    final presentations = {
      for (final id in ['s-0', 's-1', 's-2'])
        id: _single(id, date: ReleaseDate.of(2024, 4, 5)),
    };

    final forward = ArtistProfileSections.singlesRail(
      releases: releases,
      songs: songs,
      presentations: presentations,
    );
    final reversed = ArtistProfileSections.singlesRail(
      releases: releases,
      songs: songs.reversed.toList(),
      presentations: presentations,
    );

    const expected = [
      'song:s-0',
      'album:r-b',
      'song:s-1',
      'song:s-2',
      'album:r-a',
    ];
    expect(_ids(forward), expected);
    expect(_ids(reversed), expected);
  });

  test('missing and partial dates: a year sorts at its start, after an '
      'exact date that day; undated items go last, by title', () {
    final rail = ArtistProfileSections.singlesRail(
      releases: [
        _release('r-day', 'Exact', released: DateTime(2024, 1, 1)),
        _release('r-none', 'Undated Release'),
      ],
      songs: [
        base.createTrack(songId: 's-year', title: 'Year Only'),
        base.createTrack(songId: 's-month', title: 'Month Only'),
        base.createTrack(songId: 's-none', title: 'A Undated Song'),
        base.createTrack(songId: 's-nopres', title: 'No Presentation'),
      ],
      presentations: {
        's-year': _single('s-year', date: ReleaseDate.of(2024)),
        's-month': _single('s-month', date: ReleaseDate.of(2024, 3)),
        // A presentation with only a cover is still undated.
        's-none': _single('s-none', cover: '/art/none.png'),
      },
    );

    expect(_ids(rail), [
      'song:s-month',
      'album:r-day',
      'song:s-year',
      'song:s-none',
      'song:s-nopres',
      'album:r-none',
    ]);
  });

  test('a song card: its title, "Single · 1 track", its own cover or else '
      'the song\'s artwork; the album date never orders it', () {
    final track = base.createTrack(
      songId: 'hit',
      title: 'A very long single title that will not fit on one card line',
      isSingle: true,
    );
    final own = ArtistSingleSongCard(
      track: track,
      presentation: _single('hit', cover: '/art/single.png'),
    );
    final plain = ArtistSingleSongCard(track: track);

    expect(own.title, track.displayTitle);
    expect(own.summary, 'Single · 1 track');
    expect(own.notes, isEmpty);
    expect(own.artworkPath, '/art/single.png');
    expect(plain.artworkPath, track.artworkPath);
    expect(plain.sortDate, isNull);
  });

  test('no songs: the releases are returned unchanged', () {
    final releases = [
      _release('b', 'B', released: DateTime(2025)),
      _release('a', 'A', released: DateTime(2024)),
    ];
    expect(
      ArtistProfileSections.singlesRail(
        releases: releases,
        songs: const [],
        presentations: const {},
      ),
      releases,
    );
  });
}
