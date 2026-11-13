// App Update 1.2, PATCH-02 and PATCH-03: the layouts Release Studio saves
// when songs move between discs or a disc is deleted.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/application/services/edition_disc_layout.dart';

void main() {
  // Disc 1: a b, Disc 2: c d, Disc 3: e f.
  final edition = [
    for (final (song, disc) in [
      ('a', 1),
      ('b', 1),
      ('c', 2),
      ('d', 2),
      ('e', 3),
      ('f', 3),
    ])
      EditionPlacement(songId: song, discNumber: disc),
  ];

  List<String> shape(List<EditionPlacement> placements) => [
    for (final p in placements) '${p.songId}${p.discNumber}',
  ];

  group('movedToDisc', () {
    test('songs from several discs go to the end of the target, keeping '
        'their order', () {
      expect(shape(movedToDisc(edition, {'f', 'b', 'd'}, 1)), [
        'a1',
        'b1',
        'd1',
        'f1',
        'c2',
        'e3',
      ]);
    });

    test('a new disc after the last one', () {
      expect(shape(movedToDisc(edition, {'a', 'e'}, 4)), [
        'b1',
        'c2',
        'd2',
        'f3',
        'a4',
        'e4',
      ]);
    });

    test('an empty disc between others gets the songs where it begins', () {
      // As shown: Disc 1 a b, Disc 3 e f, Disc 4 c d; Disc 2 is empty.
      final gap = [
        for (final (song, disc) in [
          ('a', 1),
          ('b', 1),
          ('e', 3),
          ('f', 3),
          ('c', 4),
          ('d', 4),
        ])
          EditionPlacement(songId: song, discNumber: disc),
      ];
      expect(shape(movedToDisc(gap, {'f'}, 2)), [
        'a1',
        'b1',
        'f2',
        'e3',
        'c4',
        'd4',
      ]);
    });

    test('never adds, drops or duplicates a song', () {
      final moved = movedToDisc(edition, {'a', 'b', 'c', 'zz'}, 3);
      expect(moved.map((p) => p.songId).toSet(), {
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      });
      expect(moved, hasLength(6));
    });

    test('an unknown disc counts as Disc 1', () {
      final unknown = [
        const EditionPlacement(songId: 'x', discNumber: 0),
        ...edition,
      ];
      expect(shape(movedToDisc(unknown, {'e'}, 1)).take(4), [
        'x0',
        'a1',
        'b1',
        'e1',
      ]);
    });

    test('discs start at 1', () {
      expect(() => movedToDisc(edition, {'a'}, 0), throwsArgumentError);
    });
  });

  group('afterDeletingDisc', () {
    test('moving its songs, later discs move down one', () {
      expect(shape(afterDeletingDisc(edition, 2, moveTo: 1)), [
        'a1',
        'b1',
        'c1',
        'd1',
        'e2',
        'f2',
      ]);
    });

    test('moving its songs to a later disc, which then moves down', () {
      expect(shape(afterDeletingDisc(edition, 1, moveTo: 3)), [
        'c1',
        'd1',
        'e2',
        'f2',
        'a2',
        'b2',
      ]);
    });

    test('leaving its songs out', () {
      expect(shape(afterDeletingDisc(edition, 2)), ['a1', 'b1', 'e2', 'f2']);
    });

    test('the last disc: nothing else renumbers', () {
      expect(shape(afterDeletingDisc(edition, 3, moveTo: 2)), [
        'a1',
        'b1',
        'c2',
        'd2',
        'e2',
        'f2',
      ]);
    });

    test('an empty disc: only later discs move', () {
      expect(shape(afterDeletingDisc(edition, 4)), shape(edition));
    });

    test('its songs cannot move onto itself', () {
      expect(
        () => afterDeletingDisc(edition, 2, moveTo: 2),
        throwsArgumentError,
      );
    });
  });

  test('labelsAfterDeletingDisc: the deleted name goes, later names follow '
      'their disc', () {
    expect(labelsAfterDeletingDisc({1: 'Main', 2: 'Bonus', 3: 'Live'}, 2), {
      1: 'Main',
      2: 'Live',
    });
    expect(labelsAfterDeletingDisc({3: 'Live'}, 1), {2: 'Live'});
  });

  test('songsOnDisc and discsOf', () {
    expect(songsOnDisc(edition, 2), ['c', 'd']);
    expect(discsOf(edition), [1, 2, 3]);
  });
}
