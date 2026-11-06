import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/models/artist_roster_view.dart';

LibraryArtist artist(String id, String name, {DateTime? added}) =>
    LibraryArtist(
      artistId: id,
      name: name,
      albumCount: 1,
      songCount: 1,
      dateAdded: added ?? DateTime(2026),
    );

void main() {
  final artists = [
    artist('a', 'Ada Lune', added: DateTime(2026, 3)),
    artist('b', 'ben vale', added: DateTime(2026, 9)),
    artist('c', 'Cyd'),
    artist('d', 'Élodie'),
    artist('e', '2 Chainz Fixture'),
  ];
  final statistics = ArtistLibraryStatisticsSnapshot([
    ArtistLibraryStatistics(artist: artists[0], rank: 2, qualifiedStreams: 5),
    ArtistLibraryStatistics(artist: artists[1]),
    ArtistLibraryStatistics(artist: artists[2], rank: 1, qualifiedStreams: 9),
    ArtistLibraryStatistics(artist: artists[3]),
    ArtistLibraryStatistics(artist: artists[4]),
  ]);

  List<String> ids(ArtistRosterView view) => [
    for (final a in view.artists) a.artistId,
  ];

  test('most played lists ranked artists first, unranked by name', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: statistics,
      sort: ArtistStatisticsSort.qualifiedStreams,
    );
    expect(ids(view), ['c', 'a', 'e', 'b', 'd']);
  });

  test('by name ignores case', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: statistics,
      sort: ArtistStatisticsSort.name,
    );
    expect(ids(view).take(3), ['e', 'a', 'b']);
  });

  test('search keeps matching names, ignoring case and spaces around', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: statistics,
      sort: ArtistStatisticsSort.name,
      query: '  VALE ',
    );
    expect(ids(view), ['b']);
    expect(
      ArtistRosterView(
        artists: artists,
        statistics: statistics,
        sort: ArtistStatisticsSort.name,
        query: 'nobody',
      ).isEmpty,
      isTrue,
    );
  });

  test('pages: count, contents and where an artist is', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: statistics,
      sort: ArtistStatisticsSort.qualifiedStreams,
    );
    expect(view.pageCount(2), 3);
    expect([for (final a in view.page(1, 2)) a.artistId], ['e', 'b']);
    expect([for (final a in view.page(2, 2)) a.artistId], ['d']);
    expect(view.page(3, 2), isEmpty);
    expect(view.pageOf('d', 2), 2);
    expect(view.pageOf('missing', 2), isNull);
  });

  test('A-Z finds the first artist of a letter, accents and digits too', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: statistics,
      sort: ArtistStatisticsSort.name,
    );
    expect(view.firstFor('B')!.artistId, 'b');
    expect(view.firstFor('E')!.artistId, 'd', reason: 'Élodie files under E');
    expect(view.firstFor('#')!.artistId, 'e');
    expect(view.firstFor('D')!.artistId, 'd', reason: 'next letter with one');
  });

  test('artists without loaded statistics are listed, unranked', () {
    final view = ArtistRosterView(
      artists: artists,
      statistics: ArtistLibraryStatisticsSnapshot.empty,
      sort: ArtistStatisticsSort.qualifiedStreams,
    );
    expect(view.artists, hasLength(5));
    expect(ids(view).first, 'e', reason: 'all unranked: by name');
  });
}
