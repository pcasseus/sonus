import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/edition_numbering_repair.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

// SN-50 A-Q7D: what a previewed numbering repair would change.
LibraryTrack _track(String id, int number, {int disc = 1}) => LibraryTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist-1',
  artistName: 'Harbor Lights',
  albumId: 'album-1',
  albumTitle: 'Tidewater',
  albumEditionId: 'edition-1',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: number,
  discNumber: disc,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime.utc(2026, 10, 1),
  filePath: '/music/$id.mp3',
  isAvailable: true,
);

Map<String, (int, int)> _changes(List<LibraryTrack> tracks) => {
  for (final change in editionNumberingRepair(tracks))
    change.track.songId: (change.from, change.to),
};

void main() {
  test('numbering that counts from 1 on each disc needs no repair', () {
    expect(
      _changes([
        _track('a', 1),
        _track('b', 2),
        _track('c', 1, disc: 2),
        _track('d', 2, disc: 2),
      ]),
      isEmpty,
    );
  });

  test('gaps and a late start are closed, in the order shown', () {
    expect(_changes([_track('a', 2), _track('b', 3), _track('c', 7)]), {
      'a': (2, 1),
      'b': (3, 2),
      'c': (7, 3),
    });
  });

  test('each disc counts on its own; unknown discs count as disc 1', () {
    expect(
      _changes([
        _track('a', 1, disc: 0),
        _track('b', 3),
        _track('c', 4, disc: 2),
      ]),
      {'b': (3, 2), 'c': (4, 1)},
    );
  });

  test('a track with an unknown number keeps it and is not counted', () {
    expect(_changes([_track('a', 0), _track('b', 2)]), {'b': (2, 1)});
  });
}
