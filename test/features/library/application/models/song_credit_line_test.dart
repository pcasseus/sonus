import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/song_credit_line.dart';

void main() {
  group('songCreditLine (SN-50 C-Q1)', () {
    test('the primary artist alone', () {
      expect(songCreditLine(primaryArtistName: 'Ada Vale'), 'Ada Vale');
    });

    test('names every role in order', () {
      expect(
        songCreditLine(
          primaryArtistName: 'Ada Vale',
          coPrimaryArtists: const ['Ben Moor'],
          featuredArtists: const ['Cy Lark', 'Crane, The Lantern'],
          guestArtists: const ['Eve Shore'],
        ),
        'Ada Vale & Ben Moor Ft. Cy Lark, Crane, The Lantern with Eve Shore',
      );
    });

    test('omitting the primary keeps co-primary artists visible', () {
      expect(
        songCreditLine(
          primaryArtistName: 'Ada Vale',
          featuredArtists: const ['Cy Lark'],
          guestArtists: const ['Eve Shore'],
          omitPrimary: true,
        ),
        'Ft. Cy Lark with Eve Shore',
      );
      expect(
        songCreditLine(
          primaryArtistName: 'Ada Vale',
          coPrimaryArtists: const ['Ben Moor'],
          omitPrimary: true,
        ),
        'Ada Vale & Ben Moor',
      );
      expect(
        songCreditLine(primaryArtistName: 'Ada Vale', omitPrimary: true),
        isEmpty,
      );
    });

    test('blank names are skipped', () {
      expect(
        songCreditLine(
          primaryArtistName: 'Ada Vale',
          coPrimaryArtists: const [' '],
          guestArtists: const [''],
        ),
        'Ada Vale',
      );
    });
  });
}
